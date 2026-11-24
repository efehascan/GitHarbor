#!/bin/sh
# Release derler ve dist/Git Harbor Desktop.app paketini üretir ..
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/Git Harbor Desktop.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/GitHarbor" "$APP/Contents/MacOS/GitHarbor"
# İkon: assets/icon.png (1024 px; scripts/make-icon.swift githarbor assets/icon.png ile üretilir) → AppIcon.icns
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz assets/icon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) assets/icon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Git Harbor Desktop</string>
  <key>CFBundleIdentifier</key><string>com.efehascan.githarbor</string>
  <key>CFBundleExecutable</key><string>GitHarbor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
