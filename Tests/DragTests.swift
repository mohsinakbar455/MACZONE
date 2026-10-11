import Foundation

@main struct DragTests {
    static var checks = 0
    static var failures: [String] = []
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { failures.append(message); print("FAIL: \(message)") }
    }
    static func main() {
        let layout = ZoneLayout.columns(3)
        let screen = DragScreen(id: "main", visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), layout: layout)
        let initial = CGRect(x: 0, y: 0, width: 600, height: 400)
        let moved = initial.offsetBy(dx: 20, dy: 20)
        let pointer = CGPoint(x: 150, y: 100)
        let prefs = Preferences()
        var state = WindowDragState(initialPointer: CGPoint(x: 130, y: 80), initialFrame: initial)
        state.update(.moved, pointer: pointer, frame: moved, keys: [], preferences: prefs, screen: screen)
        expect(state.isDragging && state.selection == nil, "An ordinary drag is tracked without showing zones")
        state.update(.modifiers, pointer: pointer, frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        expect(state.selection?.selectedIDs == [layout.zones[0].id], "Pressing Shift mid-drag reveals zones without another mouse movement")
        state.update(.moved, pointer: pointer, frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        state.update(.modifiers, pointer: pointer, frame: moved, keys: [], preferences: prefs, screen: screen)
        expect(state.selection == nil, "Releasing Shift immediately cancels an overlay")
        state.update(.moved, pointer: pointer, frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        state.update(.dropped, pointer: pointer, frame: moved, keys: [], preferences: prefs, screen: screen)
        expect(state.selection == nil, "Mouse-up rechecks modifiers instead of applying a stale snap")
        state.update(.moved, pointer: pointer, frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        state.update(.dropped, pointer: CGPoint(x: 900, y: 100), frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        expect(state.selection?.selectedIDs == [layout.zones[2].id], "Mouse-up uses the final pointer position")
        state.update(.moved, pointer: pointer, frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        state.update(.modifiers, pointer: pointer, frame: moved, keys: [.shift, .option], preferences: prefs, screen: screen)
        state.update(.moved, pointer: CGPoint(x: 900, y: 100), frame: moved, keys: [.shift, .option], preferences: prefs, screen: screen)
        expect(Set(state.selection?.selectedIDs ?? []) == Set(layout.zones.map(\.id)), "Spanning selects every zone between anchor and cursor")
        state.update(.moved, pointer: pointer, frame: moved, keys: [.shift, .option], preferences: prefs, screen: screen)
        expect(state.selection?.selectedIDs == [layout.zones[0].id], "Returning to the span anchor shrinks selection")
        state.update(.modifiers, pointer: pointer, frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        expect(state.selection?.selectedIDs == [layout.zones[0].id], "Releasing Option returns to single-zone selection immediately")
        state.update(.moved, pointer: CGPoint(x: 1200, y: 800), frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        expect(state.selection?.selectedIDs == [layout.zones[2].id], "Far display boundaries remain valid drop targets")
        state.update(.moved, pointer: pointer, frame: nil, keys: [.shift], preferences: prefs, screen: nil)
        expect(state.selection == nil, "Leaving every display clears stale selection")

        var delayed = WindowDragState(initialPointer: CGPoint(x: 130, y: 80), initialFrame: initial)
        delayed.update(.moved, pointer: pointer, frame: nil, keys: [.shift], preferences: prefs, screen: screen)
        expect(!delayed.isDragging && delayed.selection == nil, "A missing AX frame cannot confirm a drag")
        delayed.update(.moved, pointer: pointer, frame: initial, keys: [.shift], preferences: prefs, screen: screen)
        expect(!delayed.isDragging && delayed.selection == nil, "Selecting text does not show zones")
        delayed.update(.modifiers, pointer: CGPoint(x: 130, y: 80), frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        expect(!delayed.isDragging, "Holding a modifier without pointer movement does not snap")
        delayed.update(.dropped, pointer: pointer, frame: moved, keys: [.shift], preferences: prefs, screen: screen)
        expect(delayed.selection?.target != nil, "A quick drag can confirm on mouse-up after AX catches up")
        delayed.update(.moved, pointer: pointer, frame: nil, keys: [.shift], preferences: prefs, screen: screen)
        expect(delayed.selection?.target != nil, "A transient AX read failure cannot hide a confirmed drag")

        var resize = WindowDragState(initialPointer: CGPoint(x: 130, y: 80), initialFrame: initial)
        resize.update(.moved, pointer: pointer, frame: CGRect(x: 20, y: 20, width: 580, height: 380), keys: [.shift], preferences: prefs, screen: screen)
        expect(!resize.isDragging && resize.selection == nil, "Resizing from the top-left does not activate snapping")
        resize.update(.moved, pointer: pointer, frame: CGRect(x: 20, y: 20, width: 500, height: 300), keys: [.shift], preferences: prefs, screen: screen)
        expect(resize.isDragging, "A window restoring its size during a drag can still activate snapping")

        var sampled = WindowDragState(initialPointer: .zero, initialFrame: initial)
        var reads = 0
        let unchangedFrame: () -> CGRect? = { reads += 1; return initial }
        for i in 0..<1000 {
            sampled.update(.moved, pointer: CGPoint(x: 3, y: 0), timestamp: Double(i)/1000,
                           frameProvider: unchangedFrame, keys: [.shift], preferences: prefs, screen: screen)
        }
        expect(reads == 0, "Stationary clicks/jitter perform no external frame reads")
        reads = 0
        for i in 0..<1000 {
            sampled.update(.moved, pointer: CGPoint(x: 30, y: 10), timestamp: 1 + Double(i)/1000,
                           frameProvider: unchangedFrame, keys: [.shift], preferences: prefs, screen: screen)
        }
        expect(reads <= 60, "A 1000 Hz content drag performs at most 60 geometry reads per second")
        expect(sampled.selection == nil, "Sampling does not mistake content dragging for a window move")
        let readsBeforeDrop = reads
        sampled.update(.dropped, pointer: pointer, timestamp: 1.9991,
                       frameProvider: { reads += 1; return moved }, keys: [.shift], preferences: prefs, screen: screen)
        expect(reads == readsBeforeDrop + 1 && sampled.selection?.target != nil, "Drop bypasses throttling to confirm a quick window drag")
        let confirmedReads = reads
        for i in 0..<1000 {
            sampled.update(.moved, pointer: pointer, timestamp: 2 + Double(i)/1000,
                           frameProvider: unchangedFrame, keys: [.shift], preferences: prefs, screen: screen)
        }
        expect(reads == confirmedReads, "Confirmed window dragging needs no further external frame reads")

        for snap in SnapModifier.allCases {
            for span in SnapModifier.allCases where span != snap {
                var custom = Preferences(); custom.setSnapKey(snap); custom.setSpanKey(span)
                var drag = WindowDragState(initialPointer: CGPoint(x: 130, y: 80), initialFrame: initial)
                drag.update(.moved, pointer: pointer, frame: moved, keys: [span], preferences: custom, screen: screen)
                expect(drag.selection == nil, "\(span.rawValue) alone does not activate \(snap.rawValue) snapping")
                drag.update(.modifiers, pointer: pointer, frame: nil, keys: [snap], preferences: custom, screen: screen)
                expect(drag.selection?.selectedIDs.count == 1, "\(snap.rawValue) activates with \(span.rawValue) as span key")
                drag.update(.modifiers, pointer: pointer, frame: nil, keys: [snap, span], preferences: custom, screen: screen)
                drag.update(.moved, pointer: CGPoint(x: 900, y: 100), frame: nil, keys: [snap, span], preferences: custom, screen: screen)
                expect(drag.selection?.selectedIDs.count == 3, "\(snap.rawValue) + \(span.rawValue) spans three zones")
                drag.update(.modifiers, pointer: CGPoint(x: 900, y: 100), frame: nil, keys: [snap], preferences: custom, screen: screen)
                expect(drag.selection?.selectedIDs == [layout.zones[2].id], "Releasing \(span.rawValue) shrinks to the hovered zone")
                drag.update(.dropped, pointer: pointer, frame: nil, keys: [span], preferences: custom, screen: screen)
                expect(drag.selection == nil, "Dropping without \(snap.rawValue) cancels snapping")
            }
        }
        state.update(.moved, pointer: pointer, frame: nil, keys: [.shift, .option], preferences: prefs, screen: screen)
        let other = DragScreen(id: "second", visibleFrame: CGRect(x: -1200, y: -800, width: 1200, height: 800), layout: layout)
        state.update(.moved, pointer: CGPoint(x: -100, y: -100), frame: nil, keys: [.shift, .option], preferences: prefs, screen: other)
        expect(state.selection?.screenID == "second" && state.selection?.selectedIDs == [layout.zones[2].id], "Cross-display movement resets the span anchor, including negative coordinates")
        var changed = layout; changed.zones.reverse()
        let changedScreen = DragScreen(id: "second", visibleFrame: other.visibleFrame, layout: changed)
        state.update(.moved, pointer: CGPoint(x: -1100, y: -100), frame: nil, keys: [.shift, .option], preferences: prefs, screen: changedScreen)
        expect(state.selection?.selectedIDs == [layout.zones[0].id], "Editing the active layout resets a stale anchor")
        var edgePrefs = prefs; edgePrefs.edgeSnap = true
        state.update(.moved, pointer: CGPoint(x: 0, y: 100), frame: nil, keys: [], preferences: edgePrefs, screen: screen)
        expect(state.selection?.target?.rect == CGRect(x: 0, y: 0, width: 0.5, height: 1), "Edge snapping remains available without modifiers")
        state.update(.dropped, pointer: CGPoint(x: 0, y: 100), frame: nil, keys: [.option], preferences: edgePrefs, screen: screen)
        expect(state.selection == nil, "An unrelated modifier suppresses edge snapping at drop")
        print("\(checks-failures.count)/\(checks) drag checks passed")
        if !failures.isEmpty { exit(1) }
    }
}
