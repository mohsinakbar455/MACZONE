#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="$PWD/build/MACZONE.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" build/module-cache
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app_path/Contents/Resources/MACZONEYellow.icns"
cp build/AppIcon.iconset/icon_512x512@2x.png "$app_path/Contents/Resources/MACZONEYellow.png"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp LICENSE "$app_path/Contents/Resources/LICENSE"
cp Resources/TilingGlass-NOTICE.txt "$app_path/Contents/Resources/TilingGlass-NOTICE.txt"
cp -R Resources/Lucide "$app_path/Contents/Resources/"
swiftc -swift-version 5 -O -g -target arm64-apple-macosx26.0 \
  -module-cache-path build/module-cache \
  -import-objc-header Sources/MACZONE/Bridge.h \
  -framework Cocoa -framework SwiftUI -framework Carbon -framework ApplicationServices \
  Sources/MACZONE/*.swift \
  -o "$app_path/Contents/MacOS/MACZONE"
maczone_signing_identity="${MACZONE_SIGNING_IDENTITY:--}"
codesign --force --deep --sign "$maczone_signing_identity" --identifier com.appfoundry.maczone "$app_path"
if [ "$maczone_signing_identity" = "-" ]; then
  printf 'Development build uses ad-hoc signing. After rebuilding, re-enable Accessibility for this build in System Settings if MACZONE reports permission needed.\n'
fi
printf 'Built %s\n' "$app_path"
