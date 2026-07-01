#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ReviewReminder"
# Use hidden dir so Spotlight doesn't index the intermediate bundle
BUNDLE_DIR=".build/bundle"
APP_PATH="$BUNDLE_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED="$INSTALL_DIR/$APP_NAME.app"

# If swift build output exists, assemble the app bundle
SWIFT_BIN=".build/release/$APP_NAME"
if [ -f "$SWIFT_BIN" ]; then
    mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
    cp "$SWIFT_BIN" "$APP_PATH/Contents/MacOS/$APP_NAME"
    cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
    [ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
    codesign --force --sign - --entitlements Resources/ReviewReminder.entitlements "$APP_PATH" 2>/dev/null || true
fi

if [ ! -d "$APP_PATH" ]; then
    echo "✗ No app bundle found. Run 'swift build -c release' or 'make release' first."
    exit 1
fi

echo "→ Installing $APP_NAME to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Stop running instance
if pgrep -x "$APP_NAME" &>/dev/null; then
    echo "→ Stopping running instance..."
    pkill -x "$APP_NAME" || true
    sleep 1
fi

# Copy to ~/Applications
rm -rf "$INSTALLED"
cp -R "$APP_PATH" "$INSTALLED"

# Remove quarantine (skip Gatekeeper prompt)
xattr -rd com.apple.quarantine "$INSTALLED" 2>/dev/null || true

echo "→ Launching $APP_NAME..."
open "$INSTALLED"

echo "✓ Installed and launched. Configure GitLab token in the tray menu → Settings."
