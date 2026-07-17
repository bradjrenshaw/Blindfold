#!/bin/bash
set -e

# Resolve paths
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(cd "$DIR/.." && pwd)"
APP_NAME="BlindfoldInstaller"
BUNDLE_DIR="$REPO_ROOT/$APP_NAME.app"

echo "== Building release binary..."
cargo build --release --manifest-path "$REPO_ROOT/installer/Cargo.toml"

echo "== Creating .app bundle structure..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

echo "== Copying executable..."
cp "$REPO_ROOT/installer/target/release/blindfold-installer" "$BUNDLE_DIR/Contents/MacOS/blindfold-installer"

echo "== Generating Info.plist..."
cat <<EOF > "$BUNDLE_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>blindfold-installer</string>
    <key>CFBundleIdentifier</key>
    <string>com.bradjrenshaw.blindfold.installer</string>
    <key>CFBundleName</key>
    <string>Blindfold Installer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.2</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.10</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "== Done! Created $BUNDLE_DIR"
