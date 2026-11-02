#!/bin/zsh
# Builds Appshot.app next to this script. Run: ./build.sh && open Appshot.app
set -euo pipefail
cd "$(dirname "$0")"

APP=Appshot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Universal binary so the same .app runs on Apple silicon and Intel Macs.
TMP=$(mktemp -d)
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" main.swift -o "$TMP/Appshot-$arch" \
    -framework AppKit -framework Carbon -framework ApplicationServices
done
lipo -create "$TMP/Appshot-arm64" "$TMP/Appshot-x86_64" -output "$APP/Contents/MacOS/Appshot"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Appshot</string>
  <key>CFBundleDisplayName</key><string>Appshot</string>
  <key>CFBundleIdentifier</key><string>local.appshot</string>
  <key>CFBundleExecutable</key><string>Appshot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Appshot opens a Terminal window to start a claude or codex CLI session.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
