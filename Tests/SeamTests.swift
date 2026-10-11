import Foundation
import CoreGraphics

@main struct SeamTests {
    static var checks = 0, failures = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
    static func main() {
        let left = SeamWindow(id: 1, frame: CGRect(x: 0, y: 30, width: 500, height: 700))
        let right = SeamWindow(id: 2, frame: CGRect(x: 510, y: 30, width: 500, height: 700))
        let tracked = [left, right]
        let pair = SeamGeometry.pairs(tracked: tracked, visibleFrames: [1: left.frame, 2: right.frame])[0]
        var gesture = SeamResizeState(pair)
        gesture.begin()
        let firstDrag = gesture.resize(by: CGPoint(x: 150, y: 0))
        expect(firstDrag.first.frame.maxX == 650 && firstDrag.second.frame.minX == 660, "Resizing preserves the shared gap")
        expect(gesture.current.center.x == 655, "Yellow handle follows the resized edge instead of staying at the old position")
        gesture.begin()
        let secondDrag = gesture.resize(by: CGPoint(x: 25, y: 0))
        expect(secondDrag.first.frame.width == 675, "A second drag starts from the previous result, without jumping back")
        let live = [UInt32(1): firstDrag.first.frame, UInt32(2): firstDrag.second.frame]
        let refreshed = SeamGeometry.pairs(tracked: tracked, visibleFrames: live)
        expect(refreshed.first?.center.x == 655, "Refreshing from stale placements uses real current window edges")
        var separated = live; separated[2] = right.frame.offsetBy(dx: 300, dy: 0)
        expect(SeamGeometry.pairs(tracked: tracked, visibleFrames: separated).isEmpty, "Moving a window away removes the orphaned handle")
        expect(SeamGeometry.pairs(tracked: tracked, visibleFrames: [1: left.frame]).isEmpty, "Closing/minimizing/hiding a partner removes its handle")
        expect(pair.panelFrame(primaryHeight: 1440).midY == 1060, "AX-to-AppKit handle coordinates match the shared edge midpoint")
        expect(SeamGeometry.exposed(pair, frontToBack: tracked, ignoring: []), "Two exposed windows show one shared handle")
        let cover = SeamWindow(id: 99, frame: CGRect(x: 450, y: 100, width: 100, height: 600))
        expect(!SeamGeometry.exposed(pair, frontToBack: [cover] + tracked, ignoring: []), "A foreground window covering the boundary hides the handle")
        let own = SeamWindow(id: 98, frame: CGRect(x: 490, y: 350, width: 30, height: 70))
        expect(SeamGeometry.exposed(pair, frontToBack: [own] + tracked, ignoring: [98]), "Our own floating handle does not hide itself")
        expect(!SeamGeometry.exposed(pair, frontToBack: [own] + tracked, ignoring: []), "Only explicitly identified handle panels are ignored")
        var overlapping = live; overlapping[2] = CGRect(x: 630, y: 30, width: 500, height: 700)
        expect(SeamGeometry.pairs(tracked: tracked, visibleFrames: overlapping).isEmpty, "An app's clamped/overlapping geometry does not produce an ambiguous edge handle")
        let top = SeamWindow(id: 3, frame: CGRect(x: -1000, y: -500, width: 600, height: 300))
        let bottom = SeamWindow(id: 4, frame: CGRect(x: -1000, y: -190, width: 600, height: 500))
        let horizontal = SeamGeometry.pairs(tracked: [top,bottom], visibleFrames: [3:top.frame,4:bottom.frame])[0]
        var horizontalState = SeamResizeState(horizontal)
        let down = horizontalState.resize(by: CGPoint(x: 0, y: -80))
        expect(down.first.frame.height == 380 && down.second.frame.minY == -110, "Horizontal handles follow AppKit's flipped drag direction")
        expect(down.center.y == -115 && !down.vertical, "Horizontal center remains between actual negative-coordinate edges")
        expect(down.panelFrame(primaryHeight: 1440).size == CGSize(width: 44,height: 8), "Horizontal native handle uses the expected orientation")
        let limited = pair.resized(by: CGPoint(x: 10000, y: 0))
        expect(limited.second.frame.width == 120 && limited.first.frame.minX == left.frame.minX && limited.second.frame.maxX == right.frame.maxX, "Extreme dragging preserves outer edges and positive sizes")
        var repeated = SeamResizeState(pair)
        var continuous = true
        for i in 0..<500 {
            repeated.begin()
            let d: CGFloat = i.isMultiple(of: 2) ? 25 : -25
            let before = repeated.current.center.x
            let result = repeated.resize(by: CGPoint(x:d,y:0))
            continuous = continuous && result.center.x == before+d && repeated.current == result
        }
        expect(continuous && repeated.current == pair, "500 consecutive resize gestures have no stale-origin jumps or drift")
        print("\(checks-failures)/\(checks) shared resize handle checks passed")
        if failures > 0 { exit(1) }
    }
}
