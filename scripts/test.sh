#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/Models.swift Tests/GeometryTests.swift -o build/tests/geometry-tests
build/tests/geometry-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/Models.swift Sources/MACZONE/DragState.swift Tests/DragTests.swift -o build/tests/drag-tests
build/tests/drag-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/Models.swift Tests/LayoutSelectionTests.swift -o build/tests/layout-selection-tests
build/tests/layout-selection-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/Models.swift Sources/MACZONE/ZoneEditing.swift Tests/ZoneEditingTests.swift -o build/tests/zone-editing-tests
build/tests/zone-editing-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/Models.swift Sources/MACZONE/WindowUpdateState.swift Tests/WindowUpdateTests.swift -o build/tests/window-update-tests
build/tests/window-update-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/WindowCompatibility.swift Tests/WindowCompatibilityTests.swift -o build/tests/window-compatibility-tests
build/tests/window-compatibility-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/Models.swift Sources/MACZONE/DragState.swift Tests/DropPointerTests.swift -o build/tests/drop-pointer-tests
build/tests/drop-pointer-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/SeamGeometry.swift Tests/SeamTests.swift -o build/tests/seam-tests
build/tests/seam-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/SeamGeometry.swift Sources/MACZONE/WindowSwap.swift Tests/WindowSwapTests.swift -o build/tests/window-swap-tests
build/tests/window-swap-tests

swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/Models.swift Tests/LayoutShortcutRuleTests.swift -o build/tests/layout-shortcut-rule-tests
build/tests/layout-shortcut-rule-tests

swiftc -swift-version 5 -module-cache-path build/module-cache MacsyZones/HotKey.swift Sources/MACZONE/ShortcutRecorder.swift Tests/ShortcutRecordingTests.swift -o build/tests/shortcut-recording-tests
build/tests/shortcut-recording-tests

swiftc -swift-version 5 -module-cache-path build/module-cache MacsyZones/HotKey.swift Sources/MACZONE/Models.swift Tests/HotkeyDeliveryTests.swift -o build/tests/hotkey-delivery-tests
build/tests/hotkey-delivery-tests

swiftc -swift-version 5 -module-cache-path build/module-cache Sources/MACZONE/AutomationCommand.swift Tests/AutomationCommandTests.swift -o build/tests/automation-command-tests
build/tests/automation-command-tests
