// MACZONE, 2026-10-10. GPL-3.0.
import SwiftUI
import AppKit

struct ShortcutRecorder: NSViewRepresentable {
    let active: Bool
    var recorded: (String?) -> Void
    func makeNSView(context: Context) -> RecorderView { RecorderView() }
    func updateNSView(_ view: RecorderView, context: Context) { view.recorded = recorded; view.active = active }
    final class RecorderView: NSView {
        var recorded: ((String?) -> Void)?
        var monitor: Any?
        var active = false { didSet { if active { install() } else if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } } }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.active else { return event }
                if event.keyCode == 53 { self.recorded?(nil); return nil }
                let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
                guard !flags.intersection([.control, .option, .command]).isEmpty else { NSSound.beep(); return nil }
                var pieces: [String] = []
                if flags.contains(.control) { pieces.append("Control") }; if flags.contains(.option) { pieces.append("Option") }; if flags.contains(.shift) { pieces.append("Shift") }; if flags.contains(.command) { pieces.append("Command") }
                guard let key = GlobalHotkey.keyName(for: event.keyCode) ?? event.charactersIgnoringModifiers?.uppercased() else { NSSound.beep(); return nil }
                pieces.append(key)
                let shortcut = pieces.joined(separator: "+")
                // Do not save a character that the registrar cannot resolve
                // back to the actual key pressed (including layout-specific keys).
                guard GlobalHotkey.parseShortcut(shortcut).keyCode == event.keyCode else { NSSound.beep(); return nil }
                self.recorded?(shortcut)
                return nil
            }
        }
    }
}
