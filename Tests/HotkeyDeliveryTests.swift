import AppKit
import Carbon

func debugLog(_ message: String) {}

@main struct HotkeyDeliveryTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var library = Library()
        library.migrateLayoutShortcuts()
        let first = library.shortcutLayout(0)!
        let second = library.shortcutLayout(1)!
        var selected = first.id
        var calls = 0
        GlobalHotkey.setup()
        let hotkey = GlobalHotkey(shortcut: "Control+Command+Shift+Y") {
            calls += 1
            selected = library.nextShortcutLayout(after: selected)!.id
            return noErr
        }
        hotkey.register()
        guard hotkey.hotKeyRef != nil else { fatalError("Fixture hotkey must register") }
        defer { hotkey.unregister() }

        // AppKit delivers Carbon hot-key events to the application target on
        // macOS 27. Exercise production setup and dispatch, not the closure
        // directly. This does not synthesize keyboard input to other apps.
        func deliver() {
            var event: EventRef?
            precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                     0, EventAttributes(kEventAttributeNone), &event) == noErr)
            var identifier = hotkey.eventHotkeyId!
            precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier) == noErr)
            _ = SendEventToEventTarget(event, GetApplicationEventTarget())
            ReleaseEvent(event)
        }
        deliver()
        guard calls == 1, selected == second.id else {
            print("FAIL: application hot-key event did not cycle the layout (callbacks: \(calls))")
            exit(1)
        }
        for _ in 1..<Library.layoutSlotCount { deliver() }
        guard calls == Library.layoutSlotCount, selected == first.id else {
            print("FAIL: repeated shortcut events must cycle and wrap exactly once per press")
            exit(1)
        }
        print("Passed 2 application hot-key delivery and layout cycle checks.")
    }
}
