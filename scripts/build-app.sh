#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Publican"
APP_DIR="$PROJECT_DIR/.build/$APP_NAME.app"
EXECUTABLE="$PROJECT_DIR/.build/release/$APP_NAME"

cd "$PROJECT_DIR"
swift build -c release
swift "$PROJECT_DIR/scripts/generate-icon.swift"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Packaging/Resources/Publican.icns" "$APP_DIR/Contents/Resources/Publican.icns"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "$APP_DIR"
