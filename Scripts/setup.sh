#!/usr/bin/env bash
set -euo pipefail

echo "→ Setting up Review Reminder development environment..."

# Check Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    echo "✗ Xcode command line tools not found. Install with: xcode-select --install"
    exit 1
fi

# Install Homebrew if missing
if ! command -v brew &>/dev/null; then
    echo "→ Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install xcodegen
if ! command -v xcodegen &>/dev/null; then
    echo "→ Installing xcodegen..."
    brew install xcodegen
fi

echo "→ Generating Xcode project..."
xcodegen generate

echo "✓ Setup complete. Run 'make open' to open in Xcode, or 'make install' to build and install."
