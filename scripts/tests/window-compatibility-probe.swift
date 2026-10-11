import AppKit

@main struct CompatibilityProbe {
    static func main() {
        let bundle = CommandLine.arguments.dropFirst().first ?? "com.adobe.PremierePro.26"
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            print("BLOCKED: target app is not running")
            exit(2)
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--watch-drop") {
            let args = Array(CommandLine.arguments.dropFirst(flag + 1))
            guard (5...6).contains(args.count), let id = UInt32(args[0]), let x = Double(args[1]), let y = Double(args[2]),
                  let w = Double(args[3]), let h = Double(args[4]), let initial = WindowServerSnapshot.frame(id: id) else {
                print("Usage: <bundleID> --watch-drop <windowID> <x> <y> <width> <height>"); exit(2)
            }
            let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
            guard rows.contains(where: { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier }) else {
                print("BLOCKED: requested window has a different owner"); exit(2)
            }
            let start = Date(); var previous = initial; var moving = false; var wasDown = false; var dropped: Date?
            let duration = args.count == 6 ? min(180, max(1, Double(args[5]) ?? 45)) : 45
            print("READY: \(duration)-second read-only capture; drag this app's OUTER titlebar with Snap into the requested zone.")
            fflush(stdout)
            while Date().timeIntervalSince(start) < duration {
                let down = NSEvent.pressedMouseButtons & 1 != 0
                guard let actual = WindowServerSnapshot.frame(id: id) else { print("BLOCKED: window disappeared"); exit(2) }
                if down && actual != previous { moving = true }
                if moving && wasDown && !down { dropped = Date(); print("DROP") }
                if actual != previous || down != wasDown {
                    print("t=\(String(format: "%.3f", Date().timeIntervalSince(start))) mouseDown=\(down) frame=\(actual)")
                    fflush(stdout)
                }
                previous = actual; wasDown = down
                if let dropped, Date().timeIntervalSince(dropped) >= 1.5 {
                    let error = [abs(actual.minX-x), abs(actual.minY-y), abs(actual.width-w), abs(actual.height-h)].max()!
                    print("\(error <= 3 ? "PASS" : "FAIL"): 1.5s after drop, expected=\(CGRect(x:x,y:y,width:w,height:h)) actual=\(actual) error_pt=\(error)")
                    if error > 3 { exit(1) }; return
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.025))
            }
            print("BLOCKED: no complete window drag observed during capture"); exit(2)
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--expect-frame") {
            let args = Array(CommandLine.arguments.dropFirst(flag + 1))
            guard args.count == 5, let id = UInt32(args[0]),
                  let x = Double(args[1]), let y = Double(args[2]),
                  let width = Double(args[3]), let height = Double(args[4]),
                  [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else {
                print("Usage: <bundleID> --expect-frame <windowID> <x> <y> <width> <height>"); exit(2)
            }
            let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
            guard rows.contains(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id &&
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier }),
                  let actual = WindowServerSnapshot.frame(id: id) else {
                print("BLOCKED: requested window is not owned by the specified running app"); exit(2)
            }
            let expected = CGRect(x: x, y: y, width: width, height: height)
            let error = [abs(actual.minX-x), abs(actual.minY-y), abs(actual.width-width), abs(actual.height-height)].max()!
            print("expected=\(expected) actual=\(actual) max_error_pt=\(error)")
            print("\(error <= 3 ? "PASS" : "FAIL"): snap landing matches the explicit target within 3 pt")
            if error > 3 { exit(1) }
            return
        }
        if CommandLine.arguments.contains("--geometry") {
            let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let ids = rows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier }
                .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
            let valid = ids.filter { WindowServerSnapshot.frame(id: $0) != nil }
            for id in valid { if let frame = WindowServerSnapshot.frame(id: id) { print("window=\(id) frame=\(frame)") } }
            print("app=\(bundle) visible_windows=\(ids.count) production_geometry_reads=\(valid.count) AX_trusted=\(AXIsProcessTrusted())")
            guard !ids.isEmpty, valid.count == ids.count else { print("FAIL: missing WindowServer drag geometry"); exit(1) }
            print("PASS: production drag geometry available without an AX round-trip")
            return
        }
        guard AXIsProcessTrusted() else {
            print("BLOCKED: read-only probe process does not have Accessibility access")
            exit(2)
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        let start = Date()
        let raw = AXClient.attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        print("app=\(bundle) windows=\(raw.count) discovery_ms=\(Int(Date().timeIntervalSince(start) * 1000))")
        var movable = 0, accepted = 0
        for element in raw {
            AXUIElementSetMessagingTimeout(element, 0.2)
            let start = Date()
            let role = AXClient.attribute(element, kAXRoleAttribute) as? String ?? "missing"
            let subrole = AXClient.attribute(element, kAXSubroleAttribute) as? String ?? "missing"
            var positionSettable = DarwinBoolean(false), sizeSettable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable)
            AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable)
            let frame = AXClient.frame(element)
            let result = AXClient.window(element, app: app)
            print("role=\(role) subrole=\(subrole) move=\(positionSettable.boolValue) resize=\(sizeSettable.boolValue) frame=\(frame != nil) accepted=\(result != nil) lookup_ms=\(Int(Date().timeIntervalSince(start) * 1000))")
            if positionSettable.boolValue && sizeSettable.boolValue && frame != nil { movable += 1; if result != nil { accepted += 1 } }
        }
        guard movable > 0 else { print("BLOCKED: no AX-movable/resizable window observed"); exit(2) }
        print("\(accepted == movable ? "PASS" : "FAIL"): accepted \(accepted)/\(movable) movable/resizable windows")
        if accepted != movable { exit(1) }
    }
}
