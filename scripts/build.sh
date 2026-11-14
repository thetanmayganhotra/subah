#!/bin/bash
# Builds Subah.app and a drag-to-install DMG into ./dist
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="2.1.0"
APP="dist/Subah.app"
DMG="dist/Subah-$VERSION.dmg"

rm -rf dist && mkdir -p dist
echo "▸ Building arm64…"
swift build -c release --triple arm64-apple-macosx14.0 >/dev/null
echo "▸ Building x86_64…"
swift build -c release --triple x86_64-apple-macosx14.0 >/dev/null
mkdir -p dist/bin
lipo -create .build/arm64-apple-macosx/release/Subah .build/x86_64-apple-macosx/release/Subah -output dist/bin/Subah
BIN=dist/bin/Subah

echo "▸ Assembling app bundle…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Subah"

echo "▸ Icon…"
swift scripts/make_icon.swift dist/icon_1024.png
ICONSET=dist/Subah.iconset && mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s dist/icon_1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) dist/icon_1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/Subah.icns"
rm -rf $ICONSET dist/icon_1024.png dist/bin

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Subah</string>
  <key>CFBundleDisplayName</key><string>Subah</string>
  <key>CFBundleIdentifier</key><string>com.tanmay.subah</string>
  <key>CFBundleExecutable</key><string>Subah</string>
  <key>CFBundleIconFile</key><string>Subah</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key><string>Subah adjusts your Mac's volume so your alarm can fade in gently.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
</dict></plist>
PLIST

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

echo "▸ DMG…"
STAGE=dist/dmg && mkdir -p $STAGE
cp -R "$APP" $STAGE/
ln -s /Applications $STAGE/Applications
hdiutil create -volname "Subah" -srcfolder $STAGE -ov -format UDZO "$DMG" >/dev/null
rm -rf $STAGE
echo "✓ $DMG"
