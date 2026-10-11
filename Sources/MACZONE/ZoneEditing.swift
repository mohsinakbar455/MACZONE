// MACZONE editor geometry. GPL-3.0.
import Foundation

enum ZoneHandle: CaseIterable {
    case move, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
    var left: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var right: Bool { self == .right || self == .topRight || self == .bottomRight }
    var top: Bool { self == .top || self == .topLeft || self == .topRight }
    var bottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
}

enum ZoneEditing {
    static func rect(_ zone: Zone, canvas: CGSize) -> CGRect {
        CGRect(x: zone.x*canvas.width+4, y: zone.y*canvas.height+4,
               width: max(12, zone.width*canvas.width-8), height: max(12, zone.height*canvas.height-8))
    }
    static func hit(_ point: CGPoint, zones: [Zone], canvas: CGSize) -> (Zone, ZoneHandle)? {
        for zone in zones.reversed() {
            let r = rect(zone, canvas: canvas)
            guard r.insetBy(dx: -4, dy: -4).contains(point) else { continue }
            let left = abs(point.x-r.minX) <= 10, right = abs(point.x-r.maxX) <= 10
            let top = abs(point.y-r.minY) <= 10, bottom = abs(point.y-r.maxY) <= 10
            let handle: ZoneHandle = top && left ? .topLeft : top && right ? .topRight :
                bottom && left ? .bottomLeft : bottom && right ? .bottomRight :
                left ? .left : right ? .right : top ? .top : bottom ? .bottom : .move
            return (zone, handle)
        }
        return nil
    }
    static func adjusted(_ original: Zone, handle: ZoneHandle, translation: CGSize, canvas: CGSize, snap: Bool) -> Zone {
        guard canvas.width > 0, canvas.height > 0 else { return original }
        var zone = original
        let dx = translation.width/canvas.width, dy = translation.height/canvas.height
        func quantize(_ x: Double) -> Double { snap ? (x*100).rounded()/100 : x }
        if handle == .move {
            zone.x = min(1-zone.width, max(0, quantize(zone.x+dx)))
            zone.y = min(1-zone.height, max(0, quantize(zone.y+dy)))
        } else {
            var left = original.x, right = original.x+original.width
            var top = original.y, bottom = original.y+original.height
            if handle.left { left = max(0, min(right-0.05, quantize(left+dx))) }
            if handle.right { right = min(1, max(left+0.05, quantize(right+dx))) }
            if handle.top { top = max(0, min(bottom-0.05, quantize(top+dy))) }
            if handle.bottom { bottom = min(1, max(top+0.05, quantize(bottom+dy))) }
            zone.x = left; zone.y = top; zone.width = right-left; zone.height = bottom-top
        }
        return zone
    }
}
