#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building release configuration..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
echo "Build output directory: $BIN_DIR"

APP_DIR="build/NotchBuddy.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Helpers"

# Copy main executable
echo "Copying NotchBuddy executable..."
cp "$BIN_DIR/NotchBuddy" "$APP_DIR/Contents/MacOS/NotchBuddy"
chmod +x "$APP_DIR/Contents/MacOS/NotchBuddy"

# Hook binary that Claude Code runs
cp "$BIN_DIR/notchbuddy-hook" "$APP_DIR/Contents/Helpers/notchbuddy-hook"

# Copy SwiftPM resource bundle (Localization.swift looks for it in Contents/Resources)
cp -R "$BIN_DIR/NotchBuddy_NotchBuddy.bundle" "$APP_DIR/Contents/Resources/"

# Write Info.plist
echo "Writing Info.plist..."
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.heyhadi.NotchBuddy</string>
    <key>CFBundleName</key>
    <string>Notch Buddy</string>
    <key>CFBundleExecutable</key>
    <string>NotchBuddy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
</dict>
</plist>
EOF

# Codesign ad-hoc
echo "Codesigning NotchBuddy.app..."
codesign --force -s - "$APP_DIR/Contents/Helpers/notchbuddy-hook"
codesign --force -s - "$APP_DIR"

echo "Done! Assembled $APP_DIR successfully."
