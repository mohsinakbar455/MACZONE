// Native interaction fixture. Compiles the production controller and snapshot
// reader unchanged. Only window writes/store are substituted: it can resize
// its own disposable windows, never another application's windows or TCC.
import AppKit

struct ManagedWindow {
    let native: NSWindow
    var id: UInt32 { UInt32(native.windowNumber) }
    var app: NSRunningApplication { .current }
}
@MainActor final class AppStore {
    static let shared = AppStore()
    var permission = true
    struct Preferences { var enabled = true; var seamResize = true }
    struct Library { var preferences = Preferences() }
    var library = Library()
    func toast(_ text: String) { print(text) }
}
@MainActor final class WindowEngine {
    var commits = 0
    func commitSharedResize(_ first: ManagedWindow, _ second: ManagedWindow, original: WindowSeam, result: WindowSeam) {
        commits += 1
    }
}
@MainActor enum AXClient {
    static func cancelFrameCorrection(_ id: UInt32) {}
    static func setFrame(_ frame: CGRect, on window: ManagedWindow, verify: Bool) -> Bool {
        let h = NSScreen.screens.first?.frame.height ?? 0
        window.native.setFrame(CGRect(x: frame.minX, y: h-frame.maxY, width: frame.width, height: frame.height), display: true)
        return true
    }
}

@MainActor final class Harness: NSObject, NSApplicationDelegate {
    let engine = WindowEngine()
    var controller: SeamController!
    var left: NSWindow!
    var right: NSWindow!
    var controls: NSWindow!
    var cover: NSWindow!
    let status = NSTextField(wrappingLabelWithString: "")
    let results = NSTextField(wrappingLabelWithString: "Running native controller checks…")
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        left = makeWindow("MACZONE resize test — left / top", .systemIndigo)
        right = makeWindow("MACZONE resize test — right / bottom", .darkGray)
        cover = makeWindow("MACZONE resize test — cover", .systemBrown)
        controls = NSWindow(contentRect: CGRect(x: 1500, y: 500, width: 650, height: 450), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        controls.title = "MACZONE shared-resize verification"
        controls.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.frame = CGRect(x: 20, y: 20, width: 610, height: 410)
        for (title, action) in [("Run native checks", #selector(runAgain)), ("Reset side by side", #selector(resetVertical)), ("Reset above / below", #selector(resetHorizontal)), ("Move right window away", #selector(separate)), ("Cover shared edge", #selector(occlude)), ("Remove cover", #selector(uncover)), ("Hide right window", #selector(hideRight)), ("Show divider menu", #selector(showMenu)), ("Close fixture", #selector(quit))] {
            let button = NSButton(title: title, target: self, action: action); stack.addArrangedSubview(button)
        }
        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        stack.addArrangedSubview(status); stack.addArrangedSubview(results); controls.contentView?.addSubview(stack)
        controller = SeamController(engine: engine)
        resetVertical()
        controls.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus() } }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        results.stringValue = "Ready — run checks with the fixture foreground."
    }
    func makeWindow(_ title: String, _ color: NSColor) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.backgroundColor = color
        window.level = .floating // Isolate the fixture from unrelated normal windows.
        return window
    }
    func apply(_ a: CGRect, _ b: CGRect) {
        cover.orderOut(nil)
        _ = AXClient.setFrame(a, on: ManagedWindow(native: left), verify: false)
        _ = AXClient.setFrame(b, on: ManagedWindow(native: right), verify: false)
        left.orderFront(nil); right.orderFront(nil)
        controller.rebuild([(ManagedWindow(native: left), a), (ManagedWindow(native: right), b)])
    }
    @objc func resetVertical() { apply(CGRect(x: 300, y: 300, width: 500, height: 650), CGRect(x: 810, y: 300, width: 500, height: 650)) }
    @objc func resetHorizontal() { apply(CGRect(x: 300, y: 200, width: 700, height: 350), CGRect(x: 300, y: 560, width: 700, height: 350)) }
    @objc func separate() { right.setFrameOrigin(CGPoint(x: right.frame.minX+150, y: right.frame.minY)) }
    @objc func occlude() {
        guard let a = WindowServerSnapshot.frame(id: UInt32(left.windowNumber)), let b = WindowServerSnapshot.frame(id: UInt32(right.windowNumber)), let pair = SeamGeometry.pairs(tracked: [SeamWindow(id: 1, frame: a), SeamWindow(id: 2, frame: b)], visibleFrames: [1: a, 2: b]).first else { return }
        let rect = CGRect(x: pair.center.x-100, y: pair.center.y-100, width: 200, height: 200)
        _ = AXClient.setFrame(rect, on: ManagedWindow(native: cover), verify: false); cover.orderFront(nil)
    }
    @objc func uncover() { cover.orderOut(nil) }
    @objc func hideRight() { right.orderOut(nil) }
    @objc func showMenu() {
        // This test button is not the divider. Wait for its mouse-up and the
        // idle reconciliation; production deliberately hides handles while
        // another control owns a left-button gesture.
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let panel = NSApp.windows.first { $0 is NSPanel && $0.isVisible && $0.alphaValue > 0 }
            results.stringValue = panel == nil ? "No visible divider" : "Opening divider menu"
            _ = (panel?.contentView as? SeamHandle)?.accessibilityPerformPress()
        }
    }
    @objc func quit() { controller.stop(); timer?.invalidate(); NSApp.terminate(nil) }
    @objc func runAgain() { Task { await runChecks() } }
    func runChecks() async {
        engine.commits = 0
        resetVertical()
        var checks = 0, failures: [String] = []
        func expect(_ ok: Bool, _ name: String) { checks += 1; if !ok { failures.append(name) } }
        func settle() async { try? await Task.sleep(nanoseconds: 400_000_000) }
        func until(_ ready: () -> Bool) async {
            for _ in 0..<40 {
                if ready() { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        func panels() -> [NSPanel] { NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.isVisible && $0.alphaValue > 0 } }
        func gesture(_ delta: CGPoint) -> Bool {
            guard let handle = panels().first?.contentView as? SeamHandle, handle.onBegin?() == true else { return false }
            let time = ProcessInfo.processInfo.systemUptime
            handle.onDrag?(delta, time); handle.onEnd?(delta, time+0.02); return true
        }
        await until { NSEvent.pressedMouseButtons == 0 && panels().count == 1 }
        expect(panels().count == 1, "Initial pair has exactly one handle")
        expect(gesture(CGPoint(x: 75, y: 0)), "First drag starts")
        await until { WindowServerSnapshot.frame(id: UInt32(left.windowNumber))?.width == 575 && panels().first?.frame.midX == 880 }
        expect(WindowServerSnapshot.frame(id: UInt32(left.windowNumber))?.width == 575 && panels().first?.frame.midX == 880, "Window and actual panel move together")
        expect(gesture(CGPoint(x: 25, y: 0)), "Second drag starts")
        await until { WindowServerSnapshot.frame(id: UInt32(left.windowNumber))?.width == 600 && panels().first?.frame.midX == 905 }
        expect(WindowServerSnapshot.frame(id: UInt32(left.windowNumber))?.width == 600 && panels().first?.frame.midX == 905, "Second drag starts from current size")
        expect(engine.commits == 2, "Both drags commit once")
        func pair() -> WindowSeam? {
            let frames = Dictionary(uniqueKeysWithValues: WindowServerSnapshot.visibleWindows().map { ($0.id,$0.frame) })
            return SeamGeometry.pairs(tracked: [SeamWindow(id:UInt32(left.windowNumber),frame:.zero),SeamWindow(id:UInt32(right.windowNumber),frame:.zero)],visibleFrames:frames).first
        }
        let beforeSwap = pair()
        if let beforeSwap { controller.swap(beforeSwap) }
        await until { engine.commits == 3 && panels().count == 1 && panels().first?.frame.midX == 905 }
        expect(WindowServerSnapshot.frame(id:UInt32(left.windowNumber)) == beforeSwap?.second.frame, "Native swap moves first window into second unequal slot")
        expect(WindowServerSnapshot.frame(id:UInt32(right.windowNumber)) == beforeSwap?.first.frame, "Native swap moves second window into first slot")
        expect(panels().count == 1 && panels().first?.frame.midX == 905, "Swapping keeps one handle on the unchanged slot boundary (actual: \(panels().map { $0.frame }))")
        if let nextPair = pair() { controller.swap(nextPair) }
        await until { engine.commits == 4 && WindowServerSnapshot.frame(id:UInt32(left.windowNumber)) == beforeSwap?.first.frame }
        expect(WindowServerSnapshot.frame(id:UInt32(left.windowNumber)) == beforeSwap?.first.frame && engine.commits == 4, "Swapping twice restores original geometry and records both actions")
        separate(); await settle(); expect(panels().isEmpty, "Moved-away window removes orphan")
        resetVertical(); await settle(); expect(panels().count == 1, "Reset has no duplicate panels")
        occlude(); await settle(); expect(panels().isEmpty, "Covering window removes handle")
        uncover(); await settle(); expect(panels().count == 1, "Uncover restores one handle")
        hideRight(); await settle(); expect(panels().isEmpty, "Hidden partner removes handle")
        resetHorizontal(); await settle()
        expect(gesture(CGPoint(x: 0, y: -100)), "Horizontal seam drag starts")
        await until { WindowServerSnapshot.frame(id: UInt32(left.windowNumber))?.height == 450 && panels().first?.frame.width == 44 }
        expect(WindowServerSnapshot.frame(id: UInt32(left.windowNumber))?.height == 450 && panels().first?.frame.width == 44, "Horizontal drag updates real windows and handle")
        controller.stop(); await settle(); expect(panels().isEmpty, "Stop closes all panels")
        results.stringValue = failures.isEmpty ? "PASS: \(checks)/\(checks) native controller checks" : "FAIL: \(failures.joined(separator: "; "))"
        controller = SeamController(engine: engine)
        resetVertical()
        controls.makeKeyAndOrderFront(nil)
    }
    func updateStatus() {
        func rect(_ window: NSWindow) -> String {
            guard let r = WindowServerSnapshot.frame(id: UInt32(window.windowNumber)) else { return "absent" }
            return "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))"
        }
        let panels = NSApp.windows.filter { $0 is NSPanel && $0.isVisible && $0.alphaValue > 0 }
        let frames = panels.map { "\(Int($0.frame.midX)),\(Int((NSScreen.screens.first?.frame.height ?? 0)-$0.frame.midY))" }.joined(separator: "; ")
        status.stringValue = "L: \(rect(left))\nR: \(rect(right))\nHandles: \(panels.count) [\(frames)] · Commits: \(engine.commits)"
    }
}
@main struct SeamNativeHarness {
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = Harness(); app.delegate = delegate; app.run()
        withExtendedLifetime(delegate) {}
    }
}
