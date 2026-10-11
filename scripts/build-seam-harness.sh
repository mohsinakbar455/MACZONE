#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests/MACZONE-Resize-QA.app/Contents/MacOS build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache \
  Sources/MACZONE/SeamGeometry.swift Sources/MACZONE/WindowSwap.swift Sources/MACZONE/SharedResize.swift Sources/MACZONE/WindowServerSnapshot.swift \
  Tests/SeamNativeHarness.swift -o build/tests/MACZONE-Resize-QA.app/Contents/MacOS/MACZONE-Seam-QA
cp Tests/SeamQA-Info.plist build/tests/MACZONE-Resize-QA.app/Contents/Info.plist
codesign --force --sign - build/tests/MACZONE-Resize-QA.app
printf 'Built disposable native fixture: %s/build/tests/MACZONE-Resize-QA.app\n' "$PWD"
