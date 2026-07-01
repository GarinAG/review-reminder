#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ReviewReminder"
SCHEME="ReviewReminder"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

echo "→ Building $APP_NAME (Release)..."

xcodebuild \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    | xcbeautify 2>/dev/null || cat

# Extract .app from archive
rm -rf "$APP_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"

# Ad-hoc sign
echo "→ Signing (ad-hoc)..."
codesign --force --sign - --deep "$APP_PATH"

echo "✓ Built: $APP_PATH"
