import Foundation

@main struct GeometryTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func near(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 1.01 }
    static func main() throws {
        let display = CGRect(x: -1920, y: 25, width: 1920, height: 1055)
        let layout = ZoneLayout.columns(2)
        let left = ZoneGeometry.frame(layout.zones[0], in: display, gap: 10, margin: 12)
        let right = ZoneGeometry.frame(layout.zones[1], in: display, gap: 10, margin: 12)
        expect(near(right.minX-left.maxX, 10), "Gap must be applied once at shared boundary")
        expect(near(left.minX-display.minX, 12), "Outer left margin applied once")
        expect(near(display.maxX-right.maxX, 12), "Outer right margin applied once")
        expect(left.minY == display.minY+12, "Top margin preserves display origin")
        let all = ZoneGeometry.union(layout.zones)!
        expect(all.rect == CGRect(x: 0, y: 0, width: 1, height: 1), "Spanning two columns fills display")
        expect(ZoneGeometry.union([]) == nil, "Empty span cannot snap")
        let appkit = CGRect(x: -1280, y: -300, width: 1280, height: 720)
        let ax = ZoneGeometry.appKitToAX(appkit, primaryHeight: 1080)
        expect(ax == CGRect(x: -1280, y: 660, width: 1280, height: 720), "Coordinate inversion supports vertically offset displays")
        var corrupt = Zone(name: "Bad", x: 1.4, y: -0.3, width: 2, height: -1)
        corrupt.constrain()
        expect(corrupt.x >= 0 && corrupt.x+corrupt.width <= 1, "Zones stay inside horizontal bounds")
        expect(corrupt.y >= 0 && corrupt.y+corrupt.height <= 1, "Zones stay inside vertical bounds")
        expect(corrupt.height >= 0.05, "Zones maintain a minimum size")
        var nan = Zone(name: "NaN", x: .nan, y: .infinity, width: -.infinity, height: .nan)
        nan.constrain()
        expect(nan.x.isFinite && nan.y.isFinite && nan.width.isFinite && nan.height.isFinite, "Nonfinite values cannot reach window APIs")
        for preset in ZoneLayout.presets {
            expect(!preset.zones.isEmpty, "Every template has zones")
            for zone in preset.zones { expect(zone.x >= 0 && zone.y >= 0 && zone.x+zone.width <= 1.001 && zone.y+zone.height <= 1.001, "Template zone bounds") }
        }
        var library = Library()
        let profile = DisplayProfile(name: "Desk", bindings: ["display": library.layouts[0].id])
        library.profiles = [profile]; library.activeProfileID = profile.id
        library.spaceBindings["display:123"] = library.layouts[1].id
        library.shortcuts["fill"] = "Control+Option+X"
        let encoded = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(Library.self, from: encoded)
        expect(decoded.layouts == library.layouts, "Layout geometry and identity survive persistence")
        expect(decoded.activeProfileID == profile.id, "Active profile survives persistence")
        expect(decoded.spaceBindings == library.spaceBindings, "Space mapping survives persistence")
        expect(decoded.shortcuts["fill"] == "Control+Option+X", "Custom binding survives persistence")
        let ids = WindowCommand.all.map(\.id)
        expect(Set(ids).count == ids.count, "Command identifiers must be unique")
        expect(WindowCommand.all.filter { $0.id.hasPrefix("zone.") }.count == 9, "All nine direct zone commands exist")
        var prefs = Preferences()
        expect(prefs.snapKey == .shift && prefs.spanKey == .option, "Default snap/span keys match the reference")
        expect(prefs.snapGesture(holding: [.shift]) == .zones(spanning: false), "Snap key reveals zones")
        expect(prefs.snapGesture(holding: [.shift, .option]) == .zones(spanning: true), "Snap plus span combines zones")
        expect(prefs.snapGesture(holding: [.option]) == .none, "Span alone does not snap")
        prefs.setSnapKey(.option)
        expect(prefs.snapKey == .option && prefs.spanKey == .shift, "Choosing the span key as snap swaps the two keys")
        prefs.setSpanKey(.command)
        expect(prefs.spanKey == .command, "Span key can be customized")
        prefs.setSpanKey(.option)
        expect(prefs.snapKey == .command && prefs.spanKey == .option, "Span changes cannot collide with snap")
        for key in SnapModifier.allCases {
            prefs.setSnapKey(key)
            expect(prefs.snapKey != prefs.spanKey, "Snap and span remain distinct")
            expect(prefs.snapGesture(holding: [key]) == .zones(spanning: false), "Every snap modifier activates zones")
            expect(prefs.snapGesture(holding: [key, prefs.spanKey]) == .zones(spanning: true), "Every modifier supports spanning")
        }
        prefs.edgeSnap = true
        expect(prefs.snapGesture(holding: []) == .edges, "Enabled edge snapping works without modifiers")
        expect(prefs.snapGesture(holding: [prefs.spanKey]) == .none, "Other modifiers suppress edge snapping")
        prefs.edgeSnap = false
        expect(prefs.snapGesture(holding: []) == .none, "Disabled edge snapping stays off")
        prefs.snapModifier = "Unknown"; prefs.spanModifier = "Shift"
        expect(prefs.snapKey == .shift && prefs.spanKey == .option, "Invalid saved modifiers have distinct safe fallbacks")
        prefs.setSnapKey(.control); prefs.setSpanKey(.command)
        let restoredPrefs = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        expect(restoredPrefs.snapKey == .control && restoredPrefs.spanKey == .command, "Modifier choices survive persistence")
        print("Passed \(checks) geometry, persistence, template, and command checks.")
    }
}
