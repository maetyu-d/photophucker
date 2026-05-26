#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Slitscan Found Image Lab"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

mkdir -p "$MACOS"

clang++ -std=c++17 -fobjc-arc native/main.mm \
  -framework Cocoa \
  -framework Metal \
  -framework MetalKit \
  -framework QuartzCore \
  -framework UniformTypeIdentifiers \
  -framework ImageIO \
  -o "$MACOS/Slitscan"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Slitscan</string>
  <key>CFBundleIdentifier</key>
  <string>local.slitscan.found-image-lab</string>
  <key>CFBundleName</key>
  <string>Slitscan Found Image Lab</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
