import Foundation

@main struct ZoneEditingTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; if !condition() { fatalError(message) }
    }
    static func close(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 1e-9 }
    static func main() {
        let zone = Zone(name: "Fixture", x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let size = CGSize(width: 1000, height: 600)
        let r = ZoneEditing.rect(zone, canvas: size)
        let points: [(ZoneHandle, CGPoint)] = [(.topLeft, CGPoint(x:r.minX,y:r.minY)), (.topRight, CGPoint(x:r.maxX,y:r.minY)), (.bottomLeft, CGPoint(x:r.minX,y:r.maxY)), (.bottomRight, CGPoint(x:r.maxX,y:r.maxY)), (.left, CGPoint(x:r.minX,y:r.midY)), (.right, CGPoint(x:r.maxX,y:r.midY)), (.top, CGPoint(x:r.midX,y:r.minY)), (.bottom, CGPoint(x:r.midX,y:r.maxY)), (.move, CGPoint(x:r.midX,y:r.midY))]
        for (handle, point) in points {
            expect(ZoneEditing.hit(point, zones: [zone], canvas: size)?.1 == handle, "Every edge/corner has its own hit target")
            let result = ZoneEditing.adjusted(zone, handle: handle, translation: CGSize(width: 30, height: 24), canvas: size, snap: false)
            expect(result.id == zone.id && result.name == zone.name, "Editing preserves zone identity")
            if handle != .move {
                expect(close(result.rect.minX, zone.x+(handle.left ? 0.03 : 0)), "Only the dragged left edge moves")
                expect(close(result.rect.maxX, zone.rect.maxX+(handle.right ? 0.03 : 0)), "Opposite right edge stays anchored")
                expect(close(result.rect.minY, zone.y+(handle.top ? 0.04 : 0)), "Only the dragged top edge moves")
                expect(close(result.rect.maxY, zone.rect.maxY+(handle.bottom ? 0.04 : 0)), "Opposite bottom edge stays anchored")
            }
            for sign in [-1.0, 1.0] {
                let clamped = ZoneEditing.adjusted(zone, handle: handle, translation: CGSize(width: sign*10000, height: sign*10000), canvas: size, snap: true)
                expect(clamped.x >= 0 && clamped.y >= 0 && clamped.rect.maxX <= 1.00001 && clamped.rect.maxY <= 1.00001, "All handles remain in bounds")
                expect(clamped.width >= 0.04999 && clamped.height >= 0.04999, "All handles retain minimum size")
            }
        }
        let smooth = ZoneEditing.adjusted(zone, handle: .right, translation: CGSize(width: 3, height: 0), canvas: size, snap: false)
        expect(close(smooth.width, 0.503), "Live resize follows sub-grid pointer movement")
        let snapped = ZoneEditing.adjusted(zone, handle: .right, translation: CGSize(width: 7, height: 0), canvas: size, snap: true)
        expect(close(snapped.rect.maxX, 0.71), "Grid snapping rounds the moved edge on completion")
        expect(ZoneEditing.hit(.zero, zones: [zone], canvas: size) == nil, "Empty canvas cannot resize a zone")
        print("Passed \(checks) edge, corner, bounds and continuous-drag checks.")
    }
}
