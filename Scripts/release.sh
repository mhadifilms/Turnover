#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
TAG="v${VERSION}"
DISPLAY_NAME="Turnover"
DMG_NAME="${DISPLAY_NAME}-${VERSION}.dmg"

# Build app and create DMG
"$(dirname "$0")/bundle-app.sh" "${VERSION}"

# Tag and push if needed, then wait for the GitHub release
if git rev-parse "${TAG}" &>/dev/null; then
    echo "Tag ${TAG} already exists, skipping tagging."
else
    echo "Tagging ${TAG} and pushing..."
    git tag "${TAG}"
    git push origin "${TAG}"
fi

echo "Waiting for GitHub release..."
for i in $(seq 1 30); do
    if gh release view "${TAG}" &>/dev/null; then
        break
    fi
    sleep 2
done

# Upload DMG to the release
echo "Uploading ${DMG_NAME}..."
gh release upload "${TAG}" "${DMG_NAME}"

echo "Done — https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/${TAG}"
