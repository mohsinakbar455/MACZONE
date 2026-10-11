import Foundation
import CoreGraphics

struct WindowSwapPlan {
    let original: WindowSeam
    var target: WindowSeam {
        var result = original
        result.first.frame = original.second.frame
        result.second.frame = original.first.frame
        return result
    }
    static func matches(_ pair: WindowSeam, frames: [UInt32: CGRect], tolerance: CGFloat = 3) -> Bool {
        [pair.first, pair.second].allSatisfy { window in
            guard let actual = frames[window.id] else { return false }
            return abs(actual.minX-window.frame.minX) <= tolerance && abs(actual.minY-window.frame.minY) <= tolerance &&
                abs(actual.width-window.frame.width) <= tolerance && abs(actual.height-window.frame.height) <= tolerance
        }
    }
}

/// Two AX writes cannot be atomic. Verify accepted geometry, and restore both
/// original slots on failure unless a newer user action has taken ownership.
@MainActor enum WindowSwapTransaction {
    enum Result: Equatable { case swapped, unavailable, cancelled, failed(restored: Bool) }
    static func run(_ plan: WindowSwapPlan, read: () -> [UInt32: CGRect],
                    write: (UInt32, CGRect) -> Bool, cancelled: () -> Bool,
                    pause: () async -> Void = { try? await Task.sleep(nanoseconds: 25_000_000) }) async -> Result {
        guard !cancelled() else { return .cancelled }
        guard plan.original.first.id != plan.original.second.id,
              WindowSwapPlan.matches(plan.original, frames: read(), tolerance: 1) else { return .unavailable }
        func accepted(_ expected: WindowSeam) async -> Bool {
            var consecutiveMatches = 0
            // Native layout/AX replies are asynchronous. The old 300 ms limit
            // could roll back a valid swap before the receiving app settled.
            for _ in 0..<40 {
                await pause()
                guard !cancelled() else { return false }
                consecutiveMatches = WindowSwapPlan.matches(expected, frames: read()) ? consecutiveMatches+1 : 0
                if consecutiveMatches >= 2 { return true }
            }
            return false
        }
        let destination = plan.target
        // AX status is an acknowledgement, not accepted geometry. A timeout
        // can still apply the first write; do not short-circuit the second
        // member or immediately move the first one back on that status alone.
        _ = write(destination.first.id, destination.first.frame)
        guard !cancelled() else { return .cancelled }
        _ = write(destination.second.id, destination.second.frame)
        if await accepted(destination) { return .swapped }
        guard !cancelled() else { return .cancelled }
        // Never substitute a different window if either member disappeared.
        let frames = read()
        guard frames[plan.original.first.id] != nil, frames[plan.original.second.id] != nil else { return .failed(restored: false) }
        _ = write(plan.original.first.id, plan.original.first.frame)
        guard !cancelled() else { return .cancelled }
        _ = write(plan.original.second.id, plan.original.second.frame)
        let restored = await accepted(plan.original)
        guard !cancelled() else { return .cancelled }
        return .failed(restored: restored)
    }
}

struct SeamPointerGesture {
    private(set) var exceededDragThreshold = false
    mutating func reset() { exceededDragThreshold = false }
    mutating func update(_ delta: CGPoint) -> Bool {
        if hypot(delta.x, delta.y) >= 4 { exceededDragThreshold = true }
        return exceededDragThreshold
    }
}
