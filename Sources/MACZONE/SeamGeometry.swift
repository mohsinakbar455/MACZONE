import Foundation
import CoreGraphics

struct SeamWindow: Equatable {
    let id: UInt32
    var frame: CGRect
}

struct WindowSeam: Equatable {
    var first: SeamWindow
    var second: SeamWindow
    let vertical: Bool
    var id: String { "\(first.id):\(second.id):\(vertical)" }
    var center: CGPoint {
        if vertical {
            return CGPoint(x: (first.frame.maxX + second.frame.minX) / 2,
                           y: (max(first.frame.minY, second.frame.minY) + min(first.frame.maxY, second.frame.maxY)) / 2)
        }
        return CGPoint(x: (max(first.frame.minX, second.frame.minX) + min(first.frame.maxX, second.frame.maxX)) / 2,
                       y: (first.frame.maxY + second.frame.minY) / 2)
    }
    func panelFrame(primaryHeight: CGFloat) -> CGRect {
        CGRect(x: center.x - (vertical ? 4 : 22), y: primaryHeight - center.y - (vertical ? 22 : 4),
               width: vertical ? 8 : 44, height: vertical ? 44 : 8)
    }
    func resized(by delta: CGPoint) -> WindowSeam {
        var result = self
        if vertical {
            let d = min(max(delta.x, 120-first.frame.width), second.frame.width-120)
            result.first.frame.size.width += d
            result.second.frame.origin.x += d; result.second.frame.size.width -= d
        } else {
            let d = min(max(-delta.y, 100-first.frame.height), second.frame.height-100)
            result.first.frame.size.height += d
            result.second.frame.origin.y += d; result.second.frame.size.height -= d
        }
        return result
    }
}

enum SeamGeometry {
    static func pairs(tracked: [SeamWindow], visibleFrames: [UInt32: CGRect]) -> [WindowSeam] {
        let windows = tracked.compactMap { item in visibleFrames[item.id].map { SeamWindow(id: item.id, frame: $0) } }
        var result: [WindowSeam] = []
        for i in windows.indices { for j in windows.indices where j > i {
            let a = windows[i], b = windows[j]
            let vertical = (-2..<30).contains(b.frame.minX-a.frame.maxX) || (-2..<30).contains(a.frame.minX-b.frame.maxX)
            let horizontal = (-2..<30).contains(b.frame.minY-a.frame.maxY) || (-2..<30).contains(a.frame.minY-b.frame.maxY)
            guard vertical || horizontal else { continue }
            let first = vertical ? (a.frame.minX < b.frame.minX ? a : b) : (a.frame.minY < b.frame.minY ? a : b)
            let second = first.id == a.id ? b : a
            let overlap = vertical ? min(a.frame.maxY,b.frame.maxY)-max(a.frame.minY,b.frame.minY) : min(a.frame.maxX,b.frame.maxX)-max(a.frame.minX,b.frame.minX)
            guard overlap > 100 else { continue }
            result.append(WindowSeam(first: first, second: second, vertical: vertical))
        } }
        return result
    }
    /// A floating handle must not sit over an unrelated foreground window.
    /// Sample just inside both adjoining edges, ignoring only our handle panels.
    static func exposed(_ seam: WindowSeam, frontToBack: [SeamWindow], ignoring: Set<UInt32>) -> Bool {
        let first = seam.vertical ? CGPoint(x: seam.first.frame.maxX-6, y: seam.center.y) : CGPoint(x: seam.center.x, y: seam.first.frame.maxY-6)
        let second = seam.vertical ? CGPoint(x: seam.second.frame.minX+6, y: seam.center.y) : CGPoint(x: seam.center.x, y: seam.second.frame.minY+6)
        func front(_ point: CGPoint) -> UInt32? {
            frontToBack.first { !ignoring.contains($0.id) && $0.frame.contains(point) }?.id
        }
        return front(first) == seam.first.id && front(second) == seam.second.id
    }
}

struct SeamResizeState {
    private var origin: WindowSeam
    private(set) var current: WindowSeam
    init(_ seam: WindowSeam) { origin = seam; current = seam }
    mutating func begin() { origin = current }
    mutating func resize(by delta: CGPoint) -> WindowSeam {
        current = origin.resized(by: delta)
        return current
    }
}
