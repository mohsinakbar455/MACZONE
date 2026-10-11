// MACZONE drag state. GPL-3.0.
// Modifier re-evaluation, confirmed drag sessions, and anchor-based spanning
// adapted from gitpcl/TilingGlass (GPL-3.0-only), commit 3a89347.
// See Resources/TilingGlass-NOTICE.txt for source paths and provenance.
import Foundation

struct DragScreen {
    let id: String
    let visibleFrame: CGRect
    let layout: ZoneLayout
}

struct DragSelection {
    let screenID: String
    let layout: ZoneLayout
    let selectedIDs: [UUID]
    var target: Zone? { ZoneGeometry.union(layout.zones.filter { selectedIDs.contains($0.id) }) }
}

enum DragUpdate { case moved, modifiers, dropped }

/// Pointer sampling seam used by the native event driver. Coordinates are AX /
/// Quartz top-left coordinates, including displays with negative origins.
enum DragPointer {
    static func location(recorded: CGPoint?, live: CGPoint, modifierOnly: Bool) -> CGPoint {
        // Global monitors run on the main queue. Under load the pointer can
        // already be elsewhere when a queued mouse-up/down is delivered. Use
        // the event's own Quartz location for both hit testing and zone choice.
        // Modifier-only events have no reliable mouse position of their own.
        if !modifierOnly, let recorded, recorded.x.isFinite, recorded.y.isFinite { return recorded }
        return live
    }
}

/// AX-coordinate state shared by the native driver and deterministic tests.
struct WindowDragState {
    let initialPointer: CGPoint
    let initialFrame: CGRect
    private(set) var isDragging = false
    private(set) var selection: DragSelection?
    private var spanAnchor: UUID?
    private var screenID: String?
    private var layout: ZoneLayout?
    private var lastFrameRead: TimeInterval?

    /// Share the production sampling gate with regression tests. High-rate
    /// pointer events must not queue cross-process frame queries; stationary
    /// clicks and already-confirmed drags do not need geometry reads at all.
    mutating func update(_ event: DragUpdate, pointer: CGPoint, timestamp: TimeInterval,
                         frameProvider: () -> CGRect?, keys: Set<SnapModifier>, preferences: Preferences, screen: DragScreen?) {
        var frame: CGRect?
        if !isDragging && hypot(pointer.x-initialPointer.x, pointer.y-initialPointer.y) > 5 &&
            (event != .moved || lastFrameRead == nil || timestamp - lastFrameRead! >= 1.0 / 60) {
            lastFrameRead = timestamp
            frame = frameProvider()
        }
        update(event, pointer: pointer, frame: frame, keys: keys, preferences: preferences, screen: screen)
    }

    mutating func update(_ event: DragUpdate, pointer: CGPoint, frame: CGRect?, keys: Set<SnapModifier>, preferences: Preferences, screen: DragScreen?) {
        // A mouse drag inside a window may just be selecting text. Wait for AX
        // to confirm the window moved, including on mouse-up after a fast drag.
        // Keep retrying while the button is held: AX can lag behind mouse events.
        if !isDragging {
            guard hypot(pointer.x-initialPointer.x, pointer.y-initialPointer.y) > 5,
                  let frame,
                  hypot(frame.minX-initialFrame.minX, frame.minY-initialFrame.minY) >= 1 else { return }
            let widthChanged = abs(frame.width-initialFrame.width) >= 5
            let heightChanged = abs(frame.height-initialFrame.height) >= 5
            let resizing = (widthChanged && (abs(frame.minX-initialFrame.minX) < 1 || abs(frame.maxX-initialFrame.maxX) < 1)) ||
                (heightChanged && (abs(frame.minY-initialFrame.minY) < 1 || abs(frame.maxY-initialFrame.maxY) < 1))
            guard !resizing else { return }
            isDragging = true
        }
        guard let screen, screen.visibleFrame.width > 0, screen.visibleFrame.height > 0 else {
            clearSelection(); return
        }
        if screenID != screen.id || layout != screen.layout { spanAnchor = nil }
        screenID = screen.id; layout = screen.layout
        switch preferences.snapGesture(holding: keys) {
        case let .zones(isSpanning):
            let area = screen.visibleFrame
            let normalized = CGPoint(x: (pointer.x-area.minX)/area.width, y: (pointer.y-area.minY)/area.height)
            let hit = Self.contains(normalized, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                ? screen.layout.zones.last { Self.contains(normalized, in: $0.rect) } : nil
            var selected: [UUID] = []
            if isSpanning {
                if let hit {
                    if spanAnchor == nil { spanAnchor = hit.id }
                    let anchor = screen.layout.zones.first { $0.id == spanAnchor } ?? hit
                    let area = anchor.rect.union(hit.rect)
                    selected = screen.layout.zones.filter {
                        let overlap = $0.rect.intersection(area)
                        return overlap.width > 1e-6 && overlap.height > 1e-6
                    }.map(\.id)
                } else { spanAnchor = nil }
            } else {
                spanAnchor = nil
                selected = hit.map { [$0.id] } ?? []
            }
            selection = DragSelection(screenID: screen.id, layout: screen.layout, selectedIDs: selected)
        case .edges:
            spanAnchor = nil
            if let zone = Self.edgeZone(pointer, screen.visibleFrame) {
                selection = DragSelection(screenID: screen.id, layout: ZoneLayout(name: "Edge snap", zones: [zone]), selectedIDs: [zone.id])
            } else { selection = nil }
        case .none:
            clearSelection()
        }
    }

    private mutating func clearSelection() {
        selection = nil; spanAnchor = nil; screenID = nil; layout = nil
    }

    static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        let epsilon = 1e-6
        return point.x >= rect.minX-epsilon && point.x <= rect.maxX+epsilon &&
            point.y >= rect.minY-epsilon && point.y <= rect.maxY+epsilon
    }

    static func edgeZone(_ p: CGPoint, _ frame: CGRect) -> Zone? {
        let left = p.x < frame.minX + 18, right = p.x > frame.maxX - 18, top = p.y < frame.minY + 18, bottom = p.y > frame.maxY - 18
        if (left || right) && (top || bottom) { return Zone(name: "Quarter", x: right ? 0.5 : 0, y: bottom ? 0.5 : 0, width: 0.5, height: 0.5) }
        if left || right { return Zone(name: "Half", x: right ? 0.5 : 0, y: 0, width: 0.5, height: 1) }
        if top { return Zone(name: "Fill", x: 0, y: 0, width: 1, height: 1) }
        if bottom { return Zone(name: "Bottom", x: 0, y: 0.5, width: 1, height: 0.5) }
        return nil
    }
}
