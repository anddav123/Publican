#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Publican"
APP_DIR="$PROJECT_DIR/.build/$APP_NAME.app"
DIST_DIR="$PROJECT_DIR/.build/dist"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
DMG_PATH="$DIST_DIR/$APP_NAME-macOS.dmg"
DMG_STAGING_DIR="$PROJECT_DIR/.build/dmg-staging"
LOCK_DIR="$PROJECT_DIR/.build/package-release.lock"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another release package build is already running." >&2
    exit 1
fi
trap 'rmdir "$LOCK_DIR"' EXIT

cd "$PROJECT_DIR"
"$PROJECT_DIR/scripts/build-app.sh" >/dev/null

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

if command -v hdiutil >/dev/null 2>&1; then
    rm -f "$DMG_PATH"
    rm -rf "$DMG_STAGING_DIR"
    mkdir -p "$DMG_STAGING_DIR"
    cp -R "$APP_DIR" "$DMG_STAGING_DIR/$APP_NAME.app"
    ln -s /Applications "$DMG_STAGING_DIR/Applications"

    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING_DIR" \
        -ov \
        -format UDZO \
        "$DMG_PATH" >/dev/null

    rm -rf "$DMG_STAGING_DIR"
fi

echo "Created:"
echo "$ZIP_PATH"
if [ -f "$DMG_PATH" ]; then
    echo "$DMG_PATH"
fi
