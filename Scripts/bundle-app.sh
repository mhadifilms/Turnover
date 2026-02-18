#!/bin/bash
set -euo pipefail

VERSION="${1:-dev}"

APP_NAME="VFXUpload"
DISPLAY_NAME="Turnover"
BUILD_DIR=".build/release"
APP_BUNDLE="${DISPLAY_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
DMG_NAME="${DISPLAY_NAME}-${VERSION}.dmg"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}" "${CONTENTS}/Resources"

cp "${BUILD_DIR}/VFXUploadApp" "${MACOS}/${APP_NAME}"

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

echo "Created ${APP_BUNDLE}"

echo "Creating DMG..."
rm -f "${DMG_NAME}"
hdiutil create -volname "${DISPLAY_NAME}" \
    -srcfolder "${APP_BUNDLE}" \
    -ov -format UDZO \
    "${DMG_NAME}"

echo "Created ${DMG_NAME}"
echo "To install: open ${DMG_NAME} and drag ${DISPLAY_NAME}.app to /Applications/"
