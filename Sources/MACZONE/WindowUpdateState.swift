// MACZONE window/overlay update coordination. GPL-3.0.
import Foundation

/// A delayed landing check must never replay a superseded frame request.
struct LatestFrameRequests {
    private var pending: [UInt32: UUID] = [:]
    mutating func begin(_ window: UInt32) -> UUID {
        let token = UUID(); pending[window] = token; return token
    }
    mutating func finish(_ window: UInt32, token: UUID) -> Bool {
        guard pending[window] == token else { return false }
        pending.removeValue(forKey: window); return true
    }
    mutating func cancel(_ window: UInt32) { pending.removeValue(forKey: window) }
    mutating func cancelAll() { pending.removeAll() }
}

struct OverlayPresentation: Equatable {
    let displayID: String
    let frame: CGRect
    let layout: ZoneLayout
    let selected: [UUID]
    let gap: Double
    let margin: Double
    let opacity: Double
    let numbers: Bool
    init(displayID: String, frame: CGRect, layout: ZoneLayout, selected: [UUID], preferences: Preferences) {
        self.displayID = displayID; self.frame = frame; self.layout = layout; self.selected = selected
        gap = preferences.gap; margin = preferences.margin; opacity = preferences.overlayOpacity; numbers = preferences.showNumbers
    }
}

struct OverlayInvalidation {
    private var previous: OverlayPresentation?
    mutating func needsUpdate(_ next: OverlayPresentation) -> Bool {
        guard previous != next else { return false }
        previous = next; return true
    }
    mutating func hide() { previous = nil }
}
