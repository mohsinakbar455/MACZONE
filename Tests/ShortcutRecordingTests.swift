import AppKit

func debugLog(_ message: String) {}

@main struct ShortcutRecordingTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let view = ShortcutRecorder.RecorderView()
        var checks = 0
        var failures: [String] = []
        // Drive the real local event monitor, then parse exactly what is saved
        // by the settings page and consumed by the Carbon registrar.
        let cases: [(UInt16, String, NSEvent.ModifierFlags)] = [
            (19, "@", [.command, .shift]),
            (18, "!", [.command, .shift]),
            (20, "#", [.command, .shift]),
            (24, "+", [.command, .shift]),
            (27, "_", [.control, .option, .shift]),
            (33, "{", [.command, .shift]),
            (30, "}", [.command, .shift]),
            (42, "|", [.command, .shift]),
            (41, ":", [.command, .shift]),
            (39, "\"", [.command, .shift]),
            (43, "<", [.command, .shift]),
            (47, ">", [.command, .shift]),
            (44, "?", [.command, .shift]),
            (50, "~", [.command, .shift]),
            (19, "2", [.command]),
            (37, "L", [.control, .option]),
            (0, "A", [.command, .shift, .capsLock]),
            (123, "\u{F702}", [.control, .option, .shift]),
            (49, " ", [.command, .shift]),
            (48, "\t", [.control, .shift]),
            (36, "\r", [.command, .shift]),
            (51, "\u{7F}", [.command, .shift])
        ]
        for (code, characters, flags) in cases {
            var saved: String?
            view.recorded = { saved = $0 }
            view.active = true
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
            NSApp.sendEvent(event)
            view.active = false
            let parsed = GlobalHotkey.parseShortcut(saved ?? "")
            checks += 1
            if parsed.keyCode != code || parsed.modifiers != flags.intersection([.command, .control, .option, .shift]) {
                failures.append("keyCode \(code), flags \(flags.rawValue): saved \(saved ?? "nil"), parsed \(String(describing: parsed.keyCode))")
            }
        }
        var cancelled = false
        view.recorded = { cancelled = $0 == nil }
        view.active = true
        NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!)
        view.active = false
        checks += 1
        if !cancelled { failures.append("Escape must cancel recording") }
        guard failures.isEmpty else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("Passed \(checks) native shortcut recording and registration mapping checks.")
    }
}
