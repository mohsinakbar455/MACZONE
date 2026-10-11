import Foundation
import CoreGraphics

@main @MainActor struct WindowSwapTests {
    static var checks = 0, failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }
    static func main() async {
        let a = SeamWindow(id: 1, frame: CGRect(x: -900, y: 30, width: 300, height: 800))
        let b = SeamWindow(id: 2, frame: CGRect(x: -590, y: 30, width: 700, height: 800))
        let original = WindowSeam(first: a, second: b, vertical: true)
        let plan = WindowSwapPlan(original: original)
        expect(plan.target.first.id == a.id && plan.target.first.frame == b.frame, "First window receives the complete second slot")
        expect(plan.target.second.id == b.id && plan.target.second.frame == a.frame, "Second window receives the complete first slot")
        expect(WindowSwapPlan(original: plan.target).target == original, "Swapping twice restores exact geometry")
        var frames = [a.id: a.frame, b.id: b.frame]
        var writes = 0
        func write(_ id: UInt32, _ frame: CGRect) -> Bool { writes += 1; frames[id] = frame; return true }
        var result = await WindowSwapTransaction.run(plan, read: { frames }, write: write, cancelled: { false }, pause: {})
        expect(result == .swapped && writes == 2, "Successful swap writes each window once")
        expect(WindowSwapPlan.matches(plan.target, frames: frames), "Unequal slots and negative coordinates land correctly")
        frames = [a.id: a.frame.offsetBy(dx: 20, dy: 0), b.id: b.frame]; writes = 0
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: write, cancelled: { false }, pause: {})
        expect(result == .unavailable && writes == 0, "A moved window invalidates a stale menu snapshot")
        frames = [a.id: a.frame]; writes = 0
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: write, cancelled: { false }, pause: {})
        expect(result == .unavailable && writes == 0, "A closed partner never targets a replacement window")
        frames = [a.id: a.frame, b.id: b.frame]; writes = 0
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: write, cancelled: { true }, pause: {})
        expect(result == .cancelled && writes == 0, "Revoked permission or cancellation prevents writes")
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: { id, frame in
            writes += 1
            if writes == 2 { return false }
            frames[id] = frame; return true
        }, cancelled: { false }, pause: {})
        expect(result == .failed(restored: true) && frames == [a.id:a.frame,b.id:b.frame], "Second-write failure restores both original slots")
        frames = [a.id: a.frame, b.id: b.frame]; writes = 0
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: { id, frame in
            writes += 1
            frames[id] = writes == 2 ? frame.insetBy(dx: -100, dy: 0) : frame
            return true
        }, cancelled: { false }, pause: {})
        expect(result == .failed(restored: true), "A falsely successful/clamped AX write is detected and restored")
        frames = [a.id: a.frame, b.id: b.frame]; writes = 0
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: { id, frame in
            writes += 1
            if writes != 1 { return false }
            frames[id] = frame; return true
        }, cancelled: { false }, pause: {})
        expect(result == .failed(restored: false), "Incomplete rollback is reported honestly")
        frames = [a.id:a.frame,b.id:b.frame]; writes = 0
        var cancelled = false
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: write, cancelled: { cancelled }, pause: { cancelled = true })
        expect(result == .cancelled && writes == 2, "A new native gesture cancels late corrections and rollback")
        frames = [a.id:a.frame,b.id:b.frame]; writes = 0
        var pauses = 0
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: { _, _ in writes += 1; return true }, cancelled: { false }, pause: {
            pauses += 1
            if pauses == 3 { frames = [a.id:b.frame,b.id:a.frame] }
        })
        expect(result == .swapped && pauses == 4, "Delayed accepted geometry is verified across two consecutive reads")
        frames = [a.id:a.frame,b.id:b.frame]; writes = 0
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: { id, frame in
            writes += 1; frames[id] = frame
            return false // AX can time out while the receiver accepts the write.
        }, cancelled: { false }, pause: {})
        expect(result == .swapped && writes == 2 && WindowSwapPlan.matches(plan.target, frames: frames),
               "Accepted window geometry must not bounce back because AX reports a timeout")
        frames = [a.id:a.frame,b.id:b.frame]; writes = 0; pauses = 0
        var delayedFrames: [UInt32:CGRect] = [:]
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: { id, frame in
            writes += 1; delayedFrames[id] = frame; return true
        }, cancelled: { false }, pause: {
            pauses += 1
            if pauses == 14 { frames = delayedFrames }
        })
        expect(result == .swapped && writes == 2 && WindowSwapPlan.matches(plan.target, frames: frames),
               "A 350 ms native layout update must not be overwritten with a rollback")
        frames = [a.id:a.frame,b.id:b.frame]; writes = 0
        result = await WindowSwapTransaction.run(plan, read: { frames }, write: write, cancelled: { false }, pause: { frames.removeValue(forKey: b.id) })
        expect(result == .failed(restored: false) && writes == 2, "Partner disappearance stops without retargeting or rollback writes")
        let top = SeamWindow(id: 3, frame: CGRect(x: 100,y: -900,width: 600,height: 300))
        let bottom = SeamWindow(id: 4, frame: CGRect(x:100,y: -590,width:600,height:500))
        let horizontal = WindowSwapPlan(original: WindowSeam(first:top,second:bottom,vertical:false))
        frames = [top.id:top.frame,bottom.id:bottom.frame]
        result = await WindowSwapTransaction.run(horizontal, read:{ frames }, write:write,cancelled:{ false },pause:{})
        expect(result == .swapped && frames[top.id] == bottom.frame && frames[bottom.id] == top.frame, "Horizontal swaps exchange full slots")
        var pointer = SeamPointerGesture()
        expect(!pointer.update(.zero), "A stationary press is a menu click")
        expect(!pointer.update(CGPoint(x:2,y:1)), "Minor pointer jitter does not resize")
        expect(pointer.update(CGPoint(x:4,y:0)), "Dragging begins at the movement threshold without a time delay")
        expect(pointer.update(.zero), "Dragging back to origin remains a drag, never a menu click")
        pointer.reset()
        expect(!pointer.update(.zero), "Each press begins with fresh click/drag state")
        print("\(checks-failures)/\(checks) window swap and click/drag checks passed")
        if failures > 0 { exit(1) }
    }
}
