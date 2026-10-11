// MACZONE, 2026-10-08. GPL-3.0.
// AX frame application and window lookup adapted from MacsyZones/Macsy.swift.
// Copyright © 2024 Oğuzhan Eroğlu. Retained attribution in LICENSE and About.
// Pointer-based AX lookup and drag-monitor lifecycle adapted from TilingGlass
// (GPL-3.0-only), commit 3a89347. See Resources/TilingGlass-NOTICE.txt.
import AppKit
import SwiftUI
import Carbon
import Combine

struct ManagedWindow {
    let element: AXUIElement
    let id: UInt32
    let app: NSRunningApplication
    var frame: CGRect? { AXClient.frame(element) }
    var dragFrame: CGRect? { WindowServerSnapshot.frame(id: id) ?? frame }
    var title: String { AXClient.attribute(element, kAXTitleAttribute) as? String ?? "" }
}

enum AXClient {
    // Window writes and their delayed landing checks run on the main thread.
    private static var frameRequests = LatestFrameRequests()
    static func cancelFrameCorrection(_ id: UInt32) { frameRequests.cancel(id) }
    static func cancelFrameCorrections() { frameRequests.cancelAll() }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        // AX timeouts apply to an individual element, not its descendants.
        // Bound every object, including custom app children returned by AX.
        AXUIElementSetMessagingTimeout(element, 0.05)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func window(_ element: AXUIElement, app: NSRunningApplication, registered: Bool = false) -> ManagedWindow? {
        let role = attribute(element, kAXRoleAttribute) as? String
        let subrole = attribute(element, kAXSubroleAttribute) as? String
        let minimized = (attribute(element, kAXMinimizedAttribute) as? Bool) == true
        let standard = role == kAXWindowRole && subrole == kAXStandardWindowSubrole
        // Test extra capabilities only on the compatibility path. A returned
        // child is never trusted as a custom window without AXWindows membership.
        let topLevel = registered || (!standard && registeredWindows(for: app).contains { CFEqual($0, element) })
        var movable = DarwinBoolean(false), resizable = DarwinBoolean(false)
        if !standard && topLevel {
            AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable)
            AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &resizable)
        }
        guard WindowCompatibility.accepts(role: role, subrole: subrole, minimized: minimized,
                                          registered: topLevel, movable: movable.boolValue, resizable: resizable.boolValue),
              (attribute(element, "AXFullScreen") as? Bool) != true else { return nil }
        var id: UInt32 = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return ManagedWindow(element: element, id: id, app: app)
    }
    private static func registeredWindows(for app: NSRunningApplication) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        return attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }
    static func windows(for app: NSRunningApplication) -> [ManagedWindow] {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier, app.activationPolicy == .regular else { return [] }
        return registeredWindows(for: app).compactMap { window($0, app: app, registered: true) }
    }
    static func focused(_ app: NSRunningApplication?) -> ManagedWindow? {
        guard let app else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        for key in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let value = attribute(application, key), CFGetTypeID(value) == AXUIElementGetTypeID(), let result = window(value as! AXUIElement, app: app) { return result }
        }
        return windows(for: app).first
    }
    /// Resolve the window actually clicked, not the previously focused app.
    /// Global mouse-down can arrive before activation/focus notifications.
    static func window(at point: CGPoint) -> ManagedWindow? {
        // Resolve the actual frontmost native window even when an app's hit
        // element is a custom AXLayoutArea with no AXWindow link (Adobe).
        let visible = WindowServerSnapshot.window(at: point)
        if let visible {
            guard visible.pid != ProcessInfo.processInfo.processIdentifier,
                  let app = NSRunningApplication(processIdentifier: visible.pid), app.activationPolicy == .regular else { return nil }
            for element in registeredWindows(for: app) {
                AXUIElementSetMessagingTimeout(element, 0.05)
                var id: UInt32 = 0
                if _AXUIElementGetWindow(element, &id) == .success, id == visible.id {
                    return window(element, app: app, registered: true)
                }
            }
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        for _ in 0..<12 {
            var candidate: AXUIElement?
            if attribute(element, kAXRoleAttribute) as? String == kAXWindowRole { candidate = element }
            else {
                for key in [kAXWindowAttribute, kAXTopLevelUIElementAttribute] {
                    if let value = attribute(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() { candidate = (value as! AXUIElement); break }
                }
            }
            if let candidate {
                var pid: pid_t = 0
                guard AXUIElementGetPid(candidate, &pid) == .success,
                      pid != ProcessInfo.processInfo.processIdentifier,
                      let app = NSRunningApplication(processIdentifier: pid) else { return nil }
                if let result = window(candidate, app: app), visible == nil || result.id == visible?.id { return result }
            }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = (parent as! AXUIElement)
        }
        return nil
    }
    /// MacsyZones' position/size ordering, with bounded landing verification.
    @discardableResult static func setFrame(_ frame: CGRect, on window: ManagedWindow, verify: Bool = true) -> Bool {
        frameRequests.cancel(window.id)
        var position = frame.origin; var size = frame.size
        guard let p = AXValueCreate(.cgPoint, &position), let s = AXValueCreate(.cgSize, &size) else { return false }
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s)
        let moved = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, p)
        let sized = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s)
        if verify {
            let token = frameRequests.begin(window.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard frameRequests.finish(window.id, token: token),
                      let landed = self.frame(window.element), abs(landed.minX - frame.minX) > 3 || abs(landed.minY - frame.minY) > 3 || abs(landed.width - frame.width) > 3 || abs(landed.height - frame.height) > 3 else { return }
                AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, p)
                AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, s)
            }
        }
        return moved == .success && sized == .success
    }
}

@MainActor final class WindowEngine {
    static let shared = WindowEngine()
    private var store: AppStore { AppStore.shared }
    private var hotkeys: [GlobalHotkey] = []
    private var monitors: [Any] = []
    private var previousApp: NSRunningApplication?
    private var history: [UInt32: CGRect] = [:]
    private var placements: [UInt32: (window: ManagedWindow, frame: CGRect)] = [:]
    private var fractionCycle: (id: UInt32, action: String, index: Int)?
    private var drag: (window: ManagedWindow, state: WindowDragState)?
    private var timer: Timer?
    private var ruleTimer: Timer?
    private var libraryObservation: AnyCancellable?
    private var permissionObservation: AnyCancellable?
    private var seenWindows = Set<UInt32>()
    private var overlay = OverlayController()
    private var previewDismissal: DispatchWorkItem?
    private var seam: SeamController?

    func start() {
        store.refreshDisplays()
        previousApp = NSWorkspace.shared.frontmostApplication
        if previousApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier { previousApp = nil }
        GlobalHotkey.setup(); registerHotkeys()
        // Release reserved chords while paused, and refresh layout-specific bindings.
        libraryObservation = store.$library.map { library in
            [String(library.preferences.enabled)] + (library.layoutShortcutSlots ?? [:]).keys.sorted().map { "\($0)=\(library.layoutShortcutSlots?[$0]?.uuidString ?? "")" } + library.layouts.map { $0.id.uuidString } +
                library.shortcuts.keys.sorted().map { "\($0)=\(library.shortcuts[$0] ?? "")" }
        }.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.registerHotkeys()
        }
        permissionObservation = store.$permission.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.registerHotkeys()
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.previousApp = app }
        }
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancelDrag(); self?.seam?.suspendForWindowGesture(); AppStore.shared.refreshSpaces() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancelDrag(); self?.seam?.suspendForWindowGesture(); AppStore.shared.refreshDisplays() } }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let granted = AXIsProcessTrusted()
                if self.store.permission != granted {
                    self.store.permission = granted
                }
            }
        }
        ruleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.applyAppRules() } }
        seam = SeamController(engine: self)
    }
    func stop() {
        previewDismissal?.cancel()
        seam?.stop()
        AXClient.cancelFrameCorrections()
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll(); timer?.invalidate(); ruleTimer?.invalidate()
        libraryObservation?.cancel(); permissionObservation?.cancel()
        hotkeys.forEach { $0.unregister() }; cancelDrag()
    }
    func registerHotkeys() {
        hotkeys.forEach { $0.unregister() }; hotkeys.removeAll(); store.shortcutFailures = []
        syncDragMonitoring()
        guard store.permission, store.library.preferences.enabled else {
            AXClient.cancelFrameCorrections()
            seam?.rebuild([])
            return
        }
        for command in store.commands {
            let chord = store.binding(for: command)
            guard !chord.isEmpty else { continue }
            if command.id.hasPrefix("layout.slot."), let slot = Int(command.id.dropFirst(12)), store.library.shortcutLayout(slot) == nil { continue }
            let hotkey = GlobalHotkey(shortcut: chord) { [weak self] in self?.perform(command.id); return noErr }
            hotkey.register(); hotkeys.append(hotkey)
            if hotkey.hotKeyRef == nil { store.shortcutFailures.append(command.title) }
        }
    }
    private func syncDragMonitoring() {
        guard store.permission, store.library.preferences.enabled else {
            monitors.forEach(NSEvent.removeMonitor); monitors.removeAll(); cancelDrag()
            return
        }
        guard monitors.isEmpty else { return }
        // Install only after trust is granted, and reinstall after a permission
        // transition. A monitor created while untrusted can miss key events.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged], handler: { [weak self] event in
            self?.mouse(event)
        }) { monitors.append(monitor) }
    }
    private func cancelDrag() { drag = nil; overlay.hide() }
    func target() -> ManagedWindow? {
        let app = NSWorkspace.shared.frontmostApplication
        return AXClient.focused(app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApp : app)
    }
    func display(for frame: CGRect) -> DisplayInfo? {
        store.displays.max { a, b in
            let ar = a.visibleAX.intersection(frame); let br = b.visibleAX.intersection(frame)
            return (ar.isNull ? 0 : ar.width * ar.height) < (br.isNull ? 0 : br.width * br.height)
        }
    }
    @discardableResult func move(_ window: ManagedWindow, to frame: CGRect, remember: Bool = true) -> Bool {
        if remember, let old = window.frame { history[window.id] = old }
        let result = AXClient.setFrame(frame, on: window)
        if result { placements[window.id] = (window, frame); seam?.rebuild(Array(placements.values)) }
        else { store.toast("This app did not accept the window size. Check Accessibility permission.") }
        return result
    }
    func commitSharedResize(_ first: ManagedWindow, _ second: ManagedWindow, original: WindowSeam, result: WindowSeam) {
        history[first.id] = original.first.frame; history[second.id] = original.second.frame
        placements[first.id] = (first, result.first.frame)
        placements[second.id] = (second, result.second.frame)
    }
    func snap(_ index: Int, display: DisplayInfo? = nil) {
        guard store.permission, store.library.preferences.enabled else { store.toast("Enable Accessibility in Permissions to move windows."); return }
        guard let window = target(), let frame = window.frame, let display = display ?? self.display(for: frame), let zone = store.layout(for: display).zones[safe: index] else { store.toast("No matching window or zone is available."); return }
        move(window, to: zoneFrame(zone, display))
    }
    func zoneFrame(_ zone: Zone, _ display: DisplayInfo) -> CGRect {
        ZoneGeometry.frame(zone, in: display.visibleAX, gap: store.library.preferences.gap, margin: store.library.preferences.margin)
    }
    func perform(_ action: String) {
        guard store.library.preferences.enabled else { return }
        if action.hasPrefix("zone."), let index = Int(action.dropFirst(5)) { snap(index); return }
        if action.hasPrefix("layout.") {
            let focusedDisplay = target()?.frame.flatMap { self.display(for: $0) }
            guard let display = focusedDisplay ?? store.displays.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) }) ?? store.selectedDisplay else { return }
            let next: ZoneLayout?
            if action == "layout.cycle" {
                next = store.library.nextShortcutLayout(after: store.layout(for: display).id)
            } else if action.hasPrefix("layout.slot."), let slot = Int(action.dropFirst(12)) {
                next = store.library.shortcutLayout(slot)
            } else if let id = UUID(uuidString: String(action.dropFirst(7))) {
                next = store.library.layouts.first { $0.id == id }
            } else { return }
            guard let next else { store.toast("Choose a layout in Shortcuts first."); return }
            store.assignLayout(next.id, to: display)
            store.toast(next.name)
            preview(display: display, layout: next)
            return
        }
        guard store.permission else { store.toast("Enable Accessibility in Permissions to move windows."); return }
        if action == "gather" { gather(); return }
        guard let window = target(), let frame = window.frame, let display = display(for: frame) else { store.toast("Select a window in another app first."); return }
        let available = display.visibleAX.insetBy(dx: store.library.preferences.margin, dy: store.library.preferences.margin)
        let layout = store.layout(for: display)
        var destination = frame
        switch action {
        case "cycle.next", "cycle.previous":
            let currentIndex = nearestZone(frame, layout, display)
            let candidates = allWindows().filter { candidate in
                guard candidate.app.bundleIdentifier != nil, let r = candidate.frame, self.display(for: r)?.id == display.id else { return false }
                return nearestZone(r, layout, display) == currentIndex
            }.sorted { $0.id < $1.id }
            guard !candidates.isEmpty else { return }
            let index = candidates.firstIndex { $0.id == window.id } ?? 0
            let next = candidates[(index + (action == "cycle.next" ? 1 : candidates.count-1)) % candidates.count]
            next.app.activate(options: []); AXUIElementPerformAction(next.element, kAXRaiseAction as CFString); return
        case "shrink.left", "shrink.right", "shrink.up", "shrink.down":
            let contained = layout.zones.map { zoneFrame($0, display) }.filter { frame.insetBy(dx: -8, dy: -8).contains(CGPoint(x: $0.midX, y: $0.midY)) }
            guard contained.count > 1 else { return }
            let direction = action.components(separatedBy: ".").last!
            let sorted = contained.sorted { a, b in direction == "left" || direction == "right" ? a.midX < b.midX : a.midY < b.midY }
            let retained = direction == "left" || direction == "up" ? Array(sorted.dropLast()) : Array(sorted.dropFirst())
            destination = retained.dropFirst().reduce(retained[0]) { $0.union($1) }
        case "restore":
            if let previous = history[window.id] { move(window, to: previous) }; return
        case "fill":
            if abs(frame.width - available.width) < 8 && abs(frame.height - available.height) < 8, let previous = history[window.id] { move(window, to: previous) }
            else { move(window, to: available) }; return
        case "center": destination.origin = CGPoint(x: available.midX - frame.width / 2, y: available.midY - frame.height / 2)
        case "height": destination.origin.y = available.minY; destination.size.height = available.height
        case "width": destination.origin.x = available.minX; destination.size.width = available.width
        case "almost": destination = available.insetBy(dx: available.width * 0.05, dy: available.height * 0.05)
        case "display.next", "display.previous":
            let current = store.displays.firstIndex { $0.id == display.id } ?? 0
            let index = (current + (action == "display.next" ? 1 : store.displays.count - 1)) % store.displays.count
            let next = store.displays[index]
            let zoneIndex = nearestZone(frame, layout, display)
            let nextLayout = store.layout(for: next)
            destination = zoneFrame(nextLayout.zones[min(zoneIndex, nextLayout.zones.count - 1)], next)
        case "tile":
            for (index, w) in allWindows().filter({ $0.frame.map { self.display(for: $0)?.id == display.id } ?? false }).enumerated() {
                move(w, to: zoneFrame(layout.zones[index % layout.zones.count], display))
            }; return
        case "left", "right", "up", "down", "expand.left", "expand.right", "expand.up", "expand.down":
            let direction = action.components(separatedBy: ".").last!
            let originIndex = nearestZone(frame, layout, display)
            let origin = zoneFrame(layout.zones[originIndex], display)
            let candidates = layout.zones.enumerated().filter { index, zone in
                guard index != originIndex else { return false }
                let r = zoneFrame(zone, display)
                switch direction { case "left": return r.midX < origin.midX - 5; case "right": return r.midX > origin.midX + 5; case "up": return r.midY < origin.midY - 5; default: return r.midY > origin.midY + 5 }
            }
            let next = candidates.min { a, b in
                let ar = zoneFrame(a.element, display); let br = zoneFrame(b.element, display)
                return hypot(ar.midX - origin.midX, ar.midY - origin.midY) < hypot(br.midX - origin.midX, br.midY - origin.midY)
            }
            if let next { destination = zoneFrame(next.element, display); if action.hasPrefix("expand") { destination = destination.union(frame) } }
            else if !action.hasPrefix("expand"), let nextDisplay = adjacentDisplay(display, direction: direction) {
                let zones = store.layout(for: nextDisplay).zones
                let nearest = zones.min { a, b in
                    let ar = zoneFrame(a, nextDisplay); let br = zoneFrame(b, nextDisplay)
                    return hypot(ar.midX-frame.midX, ar.midY-frame.midY) < hypot(br.midX-frame.midX, br.midY-frame.midY)
                }!
                destination = zoneFrame(nearest, nextDisplay)
            } else { destination = origin }
        default:
            if action.hasPrefix("half.") {
                let cycle = fractionCycle?.id == window.id && fractionCycle?.action == action ? (fractionCycle!.index + 1) % 3 : 0
                fractionCycle = (window.id, action, cycle)
                let fraction = [0.5, 1.0/3, 2.0/3][cycle]
                destination = available
                if action == "half.left" || action == "half.right" { destination.size.width *= fraction; if action == "half.right" { destination.origin.x = available.maxX - destination.width } }
                else { destination.size.height *= fraction; if action == "half.bottom" { destination.origin.y = available.maxY - destination.height } }
            } else if action.hasPrefix("third."), let index = Int(action.suffix(1)) {
                destination = CGRect(x: available.minX + available.width * Double(index) / 3, y: available.minY, width: available.width/3, height: available.height)
            } else { return }
        }
        move(window, to: destination)
    }
    private func nearestZone(_ frame: CGRect, _ layout: ZoneLayout, _ display: DisplayInfo) -> Int {
        layout.zones.indices.min { a, b in
            let ar = zoneFrame(layout.zones[a], display); let br = zoneFrame(layout.zones[b], display)
            return hypot(ar.midX - frame.midX, ar.midY - frame.midY) < hypot(br.midX - frame.midX, br.midY - frame.midY)
        } ?? 0
    }
    private func adjacentDisplay(_ display: DisplayInfo, direction: String) -> DisplayInfo? {
        store.displays.filter { d in
            guard d.id != display.id else { return false }
            switch direction { case "left": return d.visibleAX.midX < display.visibleAX.midX; case "right": return d.visibleAX.midX > display.visibleAX.midX; case "up": return d.visibleAX.midY < display.visibleAX.midY; default: return d.visibleAX.midY > display.visibleAX.midY }
        }.min { hypot($0.visibleAX.midX-display.visibleAX.midX, $0.visibleAX.midY-display.visibleAX.midY) < hypot($1.visibleAX.midX-display.visibleAX.midX, $1.visibleAX.midY-display.visibleAX.midY) }
    }
    func allWindows() -> [ManagedWindow] { NSWorkspace.shared.runningApplications.filter { !$0.isHidden }.flatMap(AXClient.windows) }
    func preview(display: DisplayInfo? = nil, layout: ZoneLayout? = nil) {
        guard let d = display ?? store.selectedDisplay else { return }
        previewDismissal?.cancel()
        overlay.show(display: d, layout: layout ?? store.layout(for: d), selected: [], preferences: store.library.preferences)
        let dismissal = DispatchWorkItem { [weak self] in
            guard let self, self.drag == nil else { return }
            self.overlay.hide()
        }
        previewDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: dismissal)
    }
    private func modifier(_ key: SnapModifier) -> NSEvent.ModifierFlags {
        switch key { case .shift: return .shift; case .option: return .option; case .control: return .control; case .command: return .command }
    }
    private func mouse(_ event: NSEvent) {
        guard store.permission, store.library.preferences.enabled else { return }
        let livePoint = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let axPoint = DragPointer.location(recorded: event.cgEvent?.location,
                                          live: CGPoint(x: livePoint.x, y: primaryHeight - livePoint.y),
                                          modifierOnly: event.type == .flagsChanged)
        let point = CGPoint(x: axPoint.x, y: primaryHeight - axPoint.y)
        switch event.type {
        case .leftMouseDown:
            cancelDrag()
            seam?.suspendForWindowGesture()
            guard let window = AXClient.window(at: axPoint) else { return }
            // Respect native resizing from any border/corner. A previous snap's
            // delayed landing check must not fight a new manual gesture.
            AXClient.cancelFrameCorrection(window.id)
            guard let frame = window.dragFrame,
                  !store.library.appRules.contains(where: { $0.bundleID == window.app.bundleIdentifier && $0.skipDrag }) else { return }
            drag = (window, WindowDragState(initialPointer: axPoint, initialFrame: frame))
        case .leftMouseDragged, .flagsChanged, .leftMouseUp:
            // A missed mouse-up must not resurrect an old overlay on the next
            // key press. Global monitoring excludes this app's own events.
            if event.type == .flagsChanged && NSEvent.pressedMouseButtons & 1 == 0 { cancelDrag(); return }
            guard var current = drag else { return }
            let prefs = store.library.preferences
            let display = store.displays.first { WindowDragState.contains(point, in: $0.screen.frame) }
            let screen = display.map { DragScreen(id: $0.id, visibleFrame: $0.visibleAX, layout: store.layout(for: $0)) }
            // Mouse events carry the current key state even if a modifier was
            // already held when monitoring began. flagsChanged covers a
            // stationary cursor; mouse-up rechecks both keys and final position.
            let keys = Set(SnapModifier.allCases.filter { event.modifierFlags.contains(modifier($0)) })
            let update: DragUpdate = event.type == .leftMouseUp ? .dropped : event.type == .flagsChanged ? .modifiers : .moved
            let draggedWindow = current.window
            current.state.update(update, pointer: axPoint, timestamp: event.timestamp,
                                 frameProvider: { draggedWindow.dragFrame }, keys: keys, preferences: prefs, screen: screen)
            if event.type == .leftMouseUp {
                defer { cancelDrag() }
                if let selection = current.state.selection, let zone = selection.target, let display {
                    history[current.window.id] = current.state.initialFrame
                    move(current.window, to: zoneFrame(zone, display), remember: false)
                }
            } else {
                drag = current
                if let selection = current.state.selection, let display {
                    overlay.show(display: display, layout: selection.layout, selected: selection.selectedIDs, preferences: prefs)
                } else { overlay.hide() }
            }
        default: break
        }
    }
    func captureSession(name: String) {
        guard store.permission else { MACZONEDelegate.current?.showWorkspace("permissions"); return }
        var counts: [String: Int] = [:]
        let records = allWindows().compactMap { window -> WindowRecord? in
            guard let id = window.app.bundleIdentifier, let frame = window.frame, let display = display(for: frame) else { return nil }
            let index = counts[id, default: 0]; counts[id] = index + 1
            let area = display.visibleAX
            return WindowRecord(bundleID: id, appName: window.app.localizedName ?? id, title: window.title, index: index, displayID: display.id, frame: frame, normalizedFrame: CGRect(x: (frame.minX-area.minX)/area.width, y: (frame.minY-area.minY)/area.height, width: frame.width/area.width, height: frame.height/area.height))
        }
        guard !records.isEmpty else { store.toast("No movable windows were found."); return }
        store.library.sessions.append(WindowSession(name: name, windows: records)); store.toast("Saved \(records.count) windows")
    }
    func restoreSession(_ session: WindowSession) {
        guard store.permission else { MACZONEDelegate.current?.showWorkspace("permissions"); return }
        let windows = allWindows(); var used = Set<UInt32>(); var restored = 0
        for record in session.windows {
            let candidates = windows.filter { $0.app.bundleIdentifier == record.bundleID && !used.contains($0.id) }
            guard let window = candidates.first(where: { $0.title == record.title }) ?? candidates[safe: record.index] ?? candidates.first,
                  let display = store.displays.first(where: { $0.id == record.displayID }) ?? store.displays.first else { continue }
            used.insert(window.id)
            let area = display.visibleAX; let n = record.normalizedFrame
            let width = min(area.width, max(100, n.width * area.width)); let height = min(area.height, max(80, n.height * area.height))
            let frame = CGRect(x: min(max(area.minX, area.minX+n.minX*area.width), area.maxX-width), y: min(max(area.minY, area.minY+n.minY*area.height), area.maxY-height), width: width, height: height)
            if move(window, to: frame) { restored += 1 }
        }
        store.toast("Restored \(restored) of \(session.windows.count) windows. Missing apps are left unopened.")
    }
    private func applyAppRules() {
        guard store.permission, store.library.preferences.enabled, !store.library.appRules.filter(\.autoPlace).isEmpty else { return }
        var current = Set<UInt32>()
        for rule in store.library.appRules where rule.autoPlace {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: rule.bundleID) {
                for window in AXClient.windows(for: app) {
                    if seenWindows.contains(window.id) { current.insert(window.id); continue }
                    let destination = rule.displayID.isEmpty ? store.displays.first : store.displays.first { $0.id == rule.displayID }
                    guard let display = destination,
                          let zone = store.library.ruleZone(rule, displayID: display.id, spaceID: store.activeSpaces[display.id] ?? store.activeSpace) else { continue }
                    if move(window, to: zoneFrame(zone, display)) { current.insert(window.id) }
                }
            }
        }
        seenWindows = current
    }
    private func gather() {
        guard let display = store.selectedDisplay else { return }
        var count = 0
        for window in allWindows() {
            guard let frame = window.frame, !store.displays.contains(where: { $0.visibleAX.intersection(frame).width > 60 && $0.visibleAX.intersection(frame).height > 60 }) else { continue }
            let area = display.visibleAX; let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
            if move(window, to: CGRect(x: area.midX-size.width/2, y: area.midY-size.height/2, width: size.width, height: size.height)) { count += 1 }
        }
        store.toast("Gathered \(count) off-screen windows")
    }
}

@MainActor final class OverlayController {
    private var panel: NSPanel?
    private var invalidation = OverlayInvalidation()
    func show(display: DisplayInfo, layout: ZoneLayout, selected: [UUID], preferences: Preferences) {
        let presentation = OverlayPresentation(displayID: display.id, frame: display.screen.visibleFrame, layout: layout, selected: selected, preferences: preferences)
        guard invalidation.needsUpdate(presentation) else { return }
        if panel == nil {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel?.identifier = NSUserInterfaceItemIdentifier("zone-overlay")
            panel?.isOpaque = false; panel?.backgroundColor = .clear; panel?.hasShadow = false
            panel?.level = .floating; panel?.ignoresMouseEvents = true; panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        panel?.setFrame(display.screen.visibleFrame, display: true)
        panel?.contentView = NSHostingView(rootView: ZoneOverlay(layout: layout, selected: selected, preferences: preferences))
        panel?.orderFrontRegardless()
    }
    func hide() { invalidation.hide(); panel?.orderOut(nil) }
}

struct ZoneOverlay: View {
    let layout: ZoneLayout; let selected: [UUID]; let preferences: Preferences
    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                let frame = ZoneGeometry.frame(zone, in: CGRect(origin: .zero, size: proxy.size), gap: preferences.gap, margin: preferences.margin)
                let active = selected.contains(zone.id)
                RoundedRectangle(cornerRadius: 12).fill((active ? Brand.yellow : Brand.navy).opacity(active ? min(0.8, preferences.overlayOpacity + 0.2) : preferences.overlayOpacity))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Brand.yellow : Brand.ice.opacity(0.7), lineWidth: active ? 3 : 1))
                    .overlay { if preferences.showNumbers { Text("\(index + 1)").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(active ? Brand.black : Brand.ice).padding(16).background(active ? Brand.yellow : Brand.navy, in: Circle()) } }
                    .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            }
        }.allowsHitTesting(false)
    }
}
