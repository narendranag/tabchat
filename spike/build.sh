#!/bin/bash
# Build the spike and wrap it in an ad-hoc signed .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Tabchat Spike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TabchatSpike "$APP/Contents/MacOS/TabchatSpike"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.narendranag.tabchat.spike</string>
    <key>CFBundleName</key><string>Tabchat Spike</string>
    <key>CFBundleDisplayName</key><string>Tabchat Spike</string>
    <key>CFBundleExecutable</key><string>TabchatSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCameraUsageDescription</key><string>Video calls in Teams and Discord.</string>
    <key>NSMicrophoneUsageDescription</key><string>Voice and video calls in Teams and Discord.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --entitlements Spike.entitlements "$APP"
echo "Built: $PWD/$APP"
