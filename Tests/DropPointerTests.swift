import Foundation

@main struct DropPointerTests {
    static var checks = 0, failures = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
    static func main() {
        let layout = ZoneLayout(name: "Work 01 replay", zones: [
            Zone(name: "Main", x: 0.24, y: 0, width: 0.76, height: 1),
            Zone(name: "Reference", x: 0, y: 0, width: 0.24, height: 1)
        ])
        let screen = DragScreen(id: "display", visibleFrame: CGRect(x: 0, y: 30, width: 5120, height: 1410), layout: layout)
        let initial = CGRect(x: 0, y: 30, width: 1229, height: 1410)
        let dropPoint = CGPoint(x: 1500, y: 100)
        // An event waits on the main queue; after mouse-up, the cursor returns
        // to Reference before the callback executes. Replaying the production
        // pointer adapter + drag state must still snap to the released-at zone.
        var returnedToOriginalZone = 0
        for i in 0..<1000 {
            let laterPointer = CGPoint(x: Double(i % 1200), y: 100)
            var state = WindowDragState(initialPointer: CGPoint(x: 500, y: 100), initialFrame: initial)
            state.update(.moved, pointer: dropPoint, frame: initial.offsetBy(dx: 1000, dy: 10), keys: [.shift], preferences: Preferences(), screen: screen)
            let resolved = DragPointer.location(recorded: dropPoint, live: laterPointer, modifierOnly: false)
            state.update(.dropped, pointer: resolved, frame: nil, keys: [.shift], preferences: Preferences(), screen: screen)
            if state.selection?.selectedIDs != [layout.zones[0].id] { returnedToOriginalZone += 1 }
        }
        expect(returnedToOriginalZone == 0, "Delayed mouse-up must not snap back to the cursor's later/original zone (\(returnedToOriginalZone)/1000 wrong)")
        expect(DragPointer.location(recorded: CGPoint(x: -900, y: -200), live: .zero, modifierOnly: false) == CGPoint(x: -900, y: -200), "Cross-display drops retain the event's recorded display")
        expect(DragPointer.location(recorded: dropPoint, live: .zero, modifierOnly: false) == dropPoint, "Mouse-down hit testing uses the actual clicked location")
        expect(DragPointer.location(recorded: .zero, live: dropPoint, modifierOnly: true) == dropPoint, "Modifier-only changes use the live pointer")
        expect(DragPointer.location(recorded: nil, live: dropPoint, modifierOnly: false) == dropPoint, "Missing Quartz event has a safe live-pointer fallback")
        expect(DragPointer.location(recorded: CGPoint(x: CGFloat.nan, y: 0), live: dropPoint, modifierOnly: false) == dropPoint, "Invalid recorded coordinates have a safe fallback")
        print("\(checks-failures)/\(checks) event-coordinate and drop replay checks passed")
        if failures > 0 { exit(1) }
    }
}
