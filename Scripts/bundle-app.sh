#!/bin/bash
set -euo pipefail

VERSION="${1:-dev}"

APP_NAME="Turnover"
DISPLAY_NAME="Turnover"
BUILD_DIR=".build/release"
OUT_DIR="build"
APP_BUNDLE="${OUT_DIR}/${DISPLAY_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
DMG_NAME="${OUT_DIR}/${DISPLAY_NAME}-${VERSION}.dmg"
DMG_STAGING="${OUT_DIR}/dmg_staging"
DMG_TEMP="${OUT_DIR}/${DISPLAY_NAME}-temp.dmg"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}" "${CONTENTS}/Resources"

cp "${BUILD_DIR}/TurnoverApp" "${MACOS}/${APP_NAME}"
cp "Assets/AppIcon.icns" "${CONTENTS}/Resources/AppIcon.icns"

cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.syncpost.vfx-upload</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "Ad-hoc signing app bundle..."
codesign --force --deep -s - "${APP_BUNDLE}"

echo "Created ${APP_BUNDLE}"

echo "Creating DMG..."
rm -f "${DMG_NAME}"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
xattr -cr "${DMG_STAGING}/${DISPLAY_NAME}.app"

# Create a read-write DMG (Applications alias added after mount)
hdiutil create -volname "${DISPLAY_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDRW \
    "${DMG_TEMP}"

# Mount the DMG
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "${DMG_TEMP}" | grep "/Volumes/" | awk -F'\t' '{print $NF}')
echo "Mounted at: ${MOUNT_DIR}"

# Create a Finder alias to /Applications (real file, not a symlink) and set its icon
APP_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"
swift - "${MOUNT_DIR}" "${APP_ICON}" <<'SWIFT'
import AppKit
import Foundation

let mountDir = CommandLine.arguments[1]
let iconFile = CommandLine.arguments[2]

// Create a Finder alias (bookmark) to /Applications
let appsURL = URL(fileURLWithPath: "/Applications")
let aliasData = try appsURL.bookmarkData(
    options: .suitableForBookmarkFile,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)
let aliasURL = URL(fileURLWithPath: mountDir).appendingPathComponent("Applications")
try URL.writeBookmarkData(aliasData, to: aliasURL)

// Set the icon explicitly
guard let image = NSImage(contentsOfFile: iconFile) else { exit(1) }
NSWorkspace.shared.setIcon(image, forFile: aliasURL.path, options: [])
SWIFT

# Style the Finder window with AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${DISPLAY_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 720, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "${DISPLAY_NAME}.app" of container window to {130, 140}
        set position of item "Applications" of container window to {390, 140}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Ensure .DS_Store is written to disk
sync

# Unmount the DMG
hdiutil detach "${MOUNT_DIR}"

# Convert to compressed read-only DMG
hdiutil convert "${DMG_TEMP}" -format UDZO -o "${DMG_NAME}"

# Clean up temp files, keep the .app and .dmg
rm -f "${DMG_TEMP}"
rm -rf "${DMG_STAGING}"

echo "Created ${DMG_NAME}"
