// Test-only startup observer, followed by lifecycle checks against this
// fixture's own windows. It never touches another application's windows.
#if MACZONE_LAUNCH_QA
import AppKit

@MainActor enum NativeLaunchAudit {
    private static var seen = Set<Int>()
    private static var timer: Timer?
    private static var observers: [NSObjectProtocol] = []
    static func start() {
        for event in [NSWindow.didBecomeKeyNotification, NSWindow.didExposeNotification, NSApplication.didUpdateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: event, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { sample() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { _ in
            MainActor.assumeIsolated { sample() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            sample(); timer?.invalidate(); timer = nil
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            let launchCount = seen.count
            Task { @MainActor in
            let checks = await checkWindowLifecycle()
            let layoutChecks = await checkLayoutPreviews()
            let report: [String: Any] = ["visibleWorkspaceCount": launchCount,
                                       "activationPolicy": NSApp.activationPolicy().rawValue,
                                       "sampledSeconds": 3, "processID": ProcessInfo.processInfo.processIdentifier,
                                       "controllerChecks": checks, "layoutPreviewChecks": layoutChecks]
            let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("launch-report.json")
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: .atomic)
            }
            }
        }
    }
    private static func checkWindowLifecycle() async -> [String: Bool] {
        guard let delegate = MACZONEDelegate.current else { return ["delegateAvailable": false] }
        func workspace() -> NSWindow? { NSApp.windows.first { $0.title == "MACZONE" && $0.isVisible } }
        func settle() async { try? await Task.sleep(nanoseconds: 100_000_000) }
        var checks: [String: Bool] = [:]
        delegate.showSettings(); await settle()
        let first = workspace()
        checks["settingsOpensWorkspace"] = first != nil && AppStore.shared.selection == "general"
        delegate.showWorkspace("layouts"); await settle()
        checks["editorReusesWindow"] = first != nil && workspace() === first
        delegate.showWorkspace("appearance"); await settle()
        delegate.showSettings(); await settle()
        checks["preferencesReuseWindow"] = first != nil && workspace() === first && AppStore.shared.selection == "appearance"
        checks["noDetachedSettingsWindow"] = !NSApp.windows.contains { $0.title == "MACZONE Settings" }
        first?.miniaturize(nil); await settle()
        delegate.showSettings(); await settle()
        checks["settingsRestoresMinimizedWindow"] = first != nil && workspace() === first && first?.isMiniaturized == false
        first?.performClose(nil); await settle()
        checks["closeStaysInMenuBar"] = workspace() == nil && !delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp)
        delegate.showSettings(); await settle()
        checks["settingsReopensSameWindow"] = first != nil && workspace() === first
        first?.performClose(nil); await settle()
        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false); await settle()
        checks["reopenDoesNotFlash"] = workspace() == nil
        return checks
    }
    private static func checkLayoutPreviews() async -> [String: Bool] {
        let store = AppStore.shared
        let engine = WindowEngine.shared
        let original = store.library
        defer { store.library = original }
        store.library.preferences.enabled = true
        store.library.layoutShortcutSlots = [:]
        store.library.setShortcutLayout(store.library.layouts[0].id, slot: 0)
        store.library.setShortcutLayout(store.library.layouts[1].id, slot: 1)
        func visible() -> Bool { NSApp.windows.contains { $0.identifier?.rawValue == "zone-overlay" && $0.isVisible } }
        func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        var checks: [String: Bool] = [:]
        engine.perform(Library.slotCommand(0))
        checks["directShortcutShowsZones"] = visible()
        await pause(1.4)
        checks["previewLastsBeyondOldTimeout"] = visible()
        await pause(0.85)
        checks["previewHidesAfterTwoSeconds"] = !visible()
        engine.perform(Library.slotCommand(0))
        await pause(0.9)
        engine.perform("layout.cycle")
        checks["cycleShowsZones"] = visible()
        let display = store.displays.first { $0.screen.frame.contains(NSEvent.mouseLocation) } ?? store.selectedDisplay
        checks["cycleSelectsSecondSlot"] = display.map { store.layout(for: $0).id == store.library.shortcutLayout(1)?.id } ?? false
        await pause(1.35)
        checks["oldTimerDoesNotHideNewPreview"] = visible()
        await pause(0.9)
        checks["latestPreviewHidesAfterTwoSeconds"] = !visible()
        return checks
    }
    private static func sample() {
        for window in NSApp.windows where window.isVisible && window.title == "MACZONE" {
            seen.insert(window.windowNumber)
        }
    }
}
#endif
