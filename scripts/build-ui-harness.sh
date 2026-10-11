#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
qa_path="$PWD/build/tests/MACZONE-UI-QA.app"
mkdir -p "$qa_path/Contents/MacOS" "$qa_path/Contents/Resources" build/module-cache
cp Resources/Info.plist "$qa_path/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.appfoundry.maczone.ui-qa "$qa_path/Contents/Info.plist"
plutil -replace CFBundleName -string MACZONE-UI-QA "$qa_path/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string MACZONE-UI-QA "$qa_path/Contents/Info.plist"
plutil -replace LSUIElement -bool false "$qa_path/Contents/Info.plist"
cp LICENSE "$qa_path/Contents/Resources/LICENSE"
cp -R Resources/Lucide "$qa_path/Contents/Resources/"
cp build/MACZONE.app/Contents/Resources/MACZONEYellow.png "$qa_path/Contents/Resources/"
cp build/MACZONE.app/Contents/Resources/MACZONEYellow.icns "$qa_path/Contents/Resources/"
swiftc -swift-version 5 -D MACZONE_UI_QA -target arm64-apple-macosx26.0 \
  -module-cache-path build/module-cache \
  -import-objc-header Sources/MACZONE/Bridge.h \
  -framework Cocoa -framework SwiftUI -framework Carbon -framework ApplicationServices \
  Sources/MACZONE/*.swift -o "$qa_path/Contents/MacOS/MACZONE"
codesign --force --sign - "$qa_path"
printf 'Built isolated UI fixture: %s\n' "$qa_path"
