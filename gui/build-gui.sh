#!/bin/bash
# build-gui.sh — compile the menu-bar helper as a .app for legacy macOS.
#
# One x86_64 binary targeting 10.6+ (MRC, no blocks/ARC/NSJSONSerialization —
# APIs that postdate 10.6 are avoided). Deployment floor below what current
# Xcode officially supports still links, as long as only ancient APIs are used.
#
# Usage: ./gui/build-gui.sh [macos-min]     (default 10.6)
set -euo pipefail

MIN="${1:-10.6}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/out/TailscaleMenu.app"
BIN="$APP/Contents/MacOS/TailscaleMenu"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

clang -x objective-c \
    -arch x86_64 \
    -mmacosx-version-min="$MIN" \
    -fno-objc-arc \
    -Wno-deprecated-declarations \
    -framework Foundation -framework AppKit \
    -o "$BIN" \
    "$ROOT/gui/TailscaleMenu.m"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>              <string>TailscaleMenu</string>
	<key>CFBundleDisplayName</key>       <string>Tailscale Menu</string>
	<key>CFBundleIdentifier</key>        <string>com.startergo.tailscale-menu</string>
	<key>CFBundleVersion</key>           <string>1.0</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundlePackageType</key>       <string>APPL</string>
	<key>CFBundleExecutable</key>        <string>TailscaleMenu</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>NSPrincipalClass</key>          <string>NSApplication</string>
	<key>LSUIElement</key>               <true/>
</dict>
</plist>
EOF

echo "OK → $APP"
echo "headless check:  $BIN --selftest"
echo "install on target: cp -R to /Applications (or run from anywhere)"
