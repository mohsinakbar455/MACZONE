import AppKit

@MainActor final class SeamController: NSObject {
    private weak var engine: WindowEngine?
    private var panels: [String: NSPanel] = [:]
    private var placed: [(window: ManagedWindow, frame: CGRect)] = []
    private var seams: [String: WindowSeam] = [:]
    private var timer: Timer?
    private var activeMenu: NSMenu?
    private var menuPair: Gesture?
    private var swapTask: Task<Void, Never>?
    private var swapToken: UUID?
    private struct Gesture {
        let original: WindowSeam
        let first: ManagedWindow
        let second: ManagedWindow
        var state: SeamResizeState
        var lastWrite: TimeInterval = 0
        var lastApplied: WindowSeam?
    }
    private var gesture: Gesture?
    init(engine: WindowEngine) {
        self.engine = engine
        super.init()
        // One WindowServer snapshot (not AX polling per window) keeps handles
        // attached after native moves, closures, minimization and Space changes.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func stop() {
        cancelActions()
        timer?.invalidate(); timer = nil; gesture = nil
        panels.values.forEach { $0.orderOut(nil); $0.close() }; panels.removeAll()
    }
    func suspendForWindowGesture() {
        cancelActions()
        gesture = nil
        panels.values.forEach { $0.orderOut(nil) }
    }
    func rebuild(_ placed: [(window: ManagedWindow, frame: CGRect)]) {
        cancelActions()
        self.placed = placed
        gesture = nil
        refresh()
    }
    private func refresh() {
        let store = AppStore.shared
        guard store.permission, store.library.preferences.enabled, store.library.preferences.seamResize else {
            cancelActions()
            gesture = nil; seams.removeAll()
            panels.values.forEach { $0.orderOut(nil) }; return
        }
        if activeMenu != nil || swapTask != nil { return }
        if let drag = gesture { refreshActiveHandle(drag); return }
        guard NSEvent.pressedMouseButtons & 1 == 0 else {
            panels.values.forEach { $0.orderOut(nil) }; return
        }
        let snapshot = WindowServerSnapshot.visibleWindows()
        let frames = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0.frame) })
        let tracked = placed.filter { !$0.window.app.isTerminated && !$0.window.app.isHidden }
            .map { SeamWindow(id: $0.window.id, frame: $0.frame) }
        let ignored = Set(panels.values.map { UInt32($0.windowNumber) })
        let visible = snapshot.map { SeamWindow(id: $0.id, frame: $0.frame) }
        let current = SeamGeometry.pairs(tracked: tracked, visibleFrames: frames)
            .filter { SeamGeometry.exposed($0, frontToBack: visible, ignoring: ignored) }
        seams = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for id in Array(panels.keys) where seams[id] == nil {
            if let panel = panels.removeValue(forKey: id) { panel.orderOut(nil); panel.close() }
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for pair in current {
            let rect = pair.panelFrame(primaryHeight: primaryHeight)
            if let panel = panels[pair.id] {
                panel.alphaValue = 1
                if panel.frame != rect { panel.setFrame(rect, display: true) }
                if !panel.isVisible { panel.orderFrontRegardless() }
                continue
            }
            let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .floating; panel.hasShadow = false
            let handle = SeamHandle(frame: CGRect(origin: .zero, size: rect.size))
            handle.vertical = pair.vertical
            handle.setAccessibilityElement(true)
            handle.setAccessibilityRole(.splitter)
            handle.setAccessibilityLabel(pair.vertical ? "Resize adjacent windows horizontally" : "Resize adjacent windows vertically")
            handle.toolTip = "Drag to resize · Click to swap windows"
            handle.setAccessibilityHelp("Drag to resize both windows. Press to open Swap Windows.")
            handle.onBegin = { [weak self] in self?.begin(pair.id) ?? false }
            handle.onDrag = { [weak self] delta, timestamp in self?.resize(delta, timestamp: timestamp) }
            handle.onEnd = { [weak self] delta, timestamp in
                self?.resize(delta, timestamp: timestamp, final: true)
                self?.finish()
            }
            handle.onClick = { [weak self] in
                self?.gesture = nil
                self?.showSwapMenu(pair.id)
            }
            panel.contentView = handle; panel.orderFrontRegardless(); panels[pair.id] = panel
        }
    }
    private func begin(_ id: String) -> Bool {
        guard swapTask == nil, activeMenu == nil, let actual = resolve(id, exposed: true) else { return false }
        AXClient.cancelFrameCorrection(actual.first.id); AXClient.cancelFrameCorrection(actual.second.id)
        gesture = actual
        for (key, panel) in panels where key != id { panel.orderOut(nil) }
        return true
    }
    private func resolve(_ id: String, exposed: Bool) -> Gesture? {
        // Refresh both members at mouse-down, never from a closure's old snap
        // rectangle. Ignore this method's own pressed button for the snapshot.
        guard AppStore.shared.permission, AppStore.shared.library.preferences.enabled, AppStore.shared.library.preferences.seamResize,
              let previous = seams[id] else { return nil }
        let snapshot = WindowServerSnapshot.visibleWindows()
        let frames = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0.frame) })
        guard let actual = SeamGeometry.pairs(tracked: [previous.first, previous.second], visibleFrames: frames).first,
              !exposed || SeamGeometry.exposed(actual, frontToBack: snapshot.map { SeamWindow(id: $0.id, frame: $0.frame) },
                                   ignoring: Set(panels.values.map { UInt32($0.windowNumber) })),
              let first = placed.first(where: { $0.window.id == actual.first.id })?.window,
              let second = placed.first(where: { $0.window.id == actual.second.id })?.window,
              !first.app.isTerminated, !second.app.isTerminated, !first.app.isHidden, !second.app.isHidden else { return nil }
        return Gesture(original: actual, first: first, second: second, state: SeamResizeState(actual))
    }
    private func cancelActions() {
        activeMenu?.cancelTracking()
        menuPair = nil
        swapTask?.cancel(); swapTask = nil; swapToken = nil
    }
    private func showSwapMenu(_ id: String) {
        guard activeMenu == nil, swapTask == nil, let pair = resolve(id, exposed: true),
              let handle = panels[id]?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "Swap Windows", action: #selector(swapFromMenu), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        menuPair = pair; activeMenu = menu
        defer { activeMenu = nil; menuPair = nil; refresh() }
        menu.popUp(positioning: nil, at: NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), in: handle)
    }
    @objc private func swapFromMenu(_ sender: NSMenuItem) {
        guard let pair = menuPair else { return }
        swap(pair.original)
    }
    /// The menu supplies captured identities/frames, never the now-focused app.
    func swap(_ original: WindowSeam) {
        guard swapTask == nil, let pair = resolve(original.id, exposed: false), pair.original == original else {
            AppStore.shared.toast("These windows changed. Open the divider menu again."); return
        }
        gesture = nil
        AXClient.cancelFrameCorrection(pair.first.id); AXClient.cancelFrameCorrection(pair.second.id)
        panels.values.forEach { $0.orderOut(nil) }
        let token = UUID(); swapToken = token
        swapTask = Task { [weak self] in
            guard let self else { return }
            let plan = WindowSwapPlan(original: original)
            let result = await WindowSwapTransaction.run(plan, read: {
                Dictionary(uniqueKeysWithValues: WindowServerSnapshot.visibleWindows().map { ($0.id, $0.frame) })
            }, write: { id, frame in
                AXClient.setFrame(frame, on: id == pair.first.id ? pair.first : pair.second, verify: false)
            }, cancelled: {
                Task.isCancelled || !AppStore.shared.permission || !AppStore.shared.library.preferences.enabled ||
                    !AppStore.shared.library.preferences.seamResize
            })
            guard self.swapToken == token else { return }
            if result == .swapped {
                self.engine?.commitSharedResize(pair.first, pair.second, original: original, result: plan.target)
                for index in self.placed.indices {
                    if self.placed[index].window.id == pair.first.id { self.placed[index].frame = plan.target.first.frame }
                    if self.placed[index].window.id == pair.second.id { self.placed[index].frame = plan.target.second.frame }
                }
            } else if result == .failed(restored: true) {
                AppStore.shared.toast("Swap unavailable for these window sizes. Original positions restored.")
            } else if result == .failed(restored: false) {
                AppStore.shared.toast("Swap could not finish. Check both windows; some positions could not be restored.")
            } else if result == .unavailable {
                AppStore.shared.toast("These windows changed. Open the divider menu again.")
            }
            self.swapTask = nil; self.swapToken = nil; self.refresh()
        }
    }
    private func resize(_ delta: CGPoint, timestamp: TimeInterval, final: Bool = false) {
        guard var drag = gesture, AppStore.shared.permission, AppStore.shared.library.preferences.enabled,
              AppStore.shared.library.preferences.seamResize else { return }
        guard final || timestamp - drag.lastWrite >= 1.0/60 else { return }
        let next = drag.state.resize(by: delta)
        guard next != drag.lastApplied else { return }
        guard next != drag.original || drag.lastApplied != nil else { return }
        drag.lastWrite = timestamp; drag.lastApplied = next
        let firstOK = AXClient.setFrame(next.first.frame, on: drag.first, verify: false)
        let secondOK = AXClient.setFrame(next.second.frame, on: drag.second, verify: false)
        guard firstOK && secondOK else {
            gesture = nil; panels.values.forEach { $0.orderOut(nil) }
            AppStore.shared.toast("One of these windows could not be resized. Its app may limit the window size.")
            return
        }
        gesture = drag
        refreshActiveHandle(drag)
    }
    private func refreshActiveHandle(_ drag: Gesture) {
        guard let panel = panels[drag.original.id] else { return }
        let frames = Dictionary(uniqueKeysWithValues: WindowServerSnapshot.visibleWindows().map { ($0.id, $0.frame) })
        if let actual = SeamGeometry.pairs(tracked: [drag.original.first, drag.original.second], visibleFrames: frames).first {
            panel.alphaValue = 1
            panel.setFrame(actual.panelFrame(primaryHeight: NSScreen.screens.first?.frame.height ?? 0), display: true)
        } else {
            // If an app clamps/refuses a size, do not draw a fake border. Keep
            // the tracking window alive until mouse-up, then reconcile/remove it.
            panel.alphaValue = 0
        }
    }
    private func finish() {
        if let drag = gesture, drag.lastApplied != nil {
            var result = drag.state.current
            result.first.frame = WindowServerSnapshot.frame(id: drag.first.id) ?? result.first.frame
            result.second.frame = WindowServerSnapshot.frame(id: drag.second.id) ?? result.second.frame
            engine?.commitSharedResize(drag.first, drag.second, original: drag.original, result: result)
            for index in placed.indices {
                if placed[index].window.id == drag.first.id { placed[index].frame = result.first.frame }
                if placed[index].window.id == drag.second.id { placed[index].frame = result.second.frame }
            }
        }
        gesture = nil
        // The periodic refresh reconciles with accepted, not requested, frames.
        refresh()
    }
}

final class SeamHandle: NSView {
    var vertical = true
    var onBegin: (() -> Bool)?
    var onDrag: ((CGPoint, TimeInterval) -> Void)?
    var onEnd: ((CGPoint, TimeInterval) -> Void)?
    var onClick: (() -> Void)?
    private var origin = CGPoint.zero
    private var dragging = false
    private var pointerGesture = SeamPointerGesture()
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onClick?(); return onClick != nil }
    override func draw(_ dirtyRect: NSRect) { NSColor(calibratedRed: 1, green: 225/255, blue: 79/255, alpha: 0.8).setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown) }
    private func point(_ event: NSEvent) -> CGPoint { event.cgEvent?.unflippedLocation ?? NSEvent.mouseLocation }
    override func mouseDown(with event: NSEvent) { origin = point(event); pointerGesture.reset(); dragging = onBegin?() ?? false }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }; let p = point(event)
        let delta = CGPoint(x: p.x-origin.x, y: p.y-origin.y)
        if pointerGesture.update(delta) { onDrag?(delta, event.timestamp) }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }; dragging = false; let p = point(event)
        let delta = CGPoint(x: p.x-origin.x, y: p.y-origin.y)
        if pointerGesture.update(delta) { onEnd?(delta, event.timestamp) }
        else { onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}
