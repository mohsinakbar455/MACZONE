#!/bin/bash
# Read-only production AX lookup probe. Never moves windows or reads titles.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests build/module-cache
awk '/^struct ManagedWindow \{/{copy=1} /^@MainActor final class WindowEngine/{copy=0} copy {print}' Sources/MACZONE/WindowEngine.swift > build/tests/AXClientProbeSource.swift
# Supply the imports removed by the bounded extraction above.
swiftc -swift-version 5 -module-cache-path build/module-cache -import-objc-header Sources/MACZONE/Bridge.h \
  -framework Cocoa -framework ApplicationServices \
  Sources/MACZONE/Models.swift Sources/MACZONE/WindowUpdateState.swift Sources/MACZONE/WindowCompatibility.swift Sources/MACZONE/WindowServerSnapshot.swift \
  build/tests/AXClientProbeSource.swift scripts/tests/window-compatibility-probe.swift \
  -o build/tests/window-compatibility-probe
build/tests/window-compatibility-probe "$@"
