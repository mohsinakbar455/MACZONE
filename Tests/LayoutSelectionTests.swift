import Foundation

@main struct LayoutSelectionTests {
    static var checks = 0
    static var failures = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }
    static func main() throws {
        var library = Library()
        let fallback = library.layouts[0].id, old = library.layouts[1].id, next = library.layouts[2].id
        library.preferences.perSpace = true
        library.displayBindings["display"] = fallback
        library.spaceBindings["display:1"] = old
        library.spaceBindings["display:2"] = old
        library.assignLayout(next, displayID: "display", spaceID: "1")
        expect(library.layout(displayID: "display", spaceID: "1").id == next, "Menu/Apply selection replaces the current Space override")
        expect(library.layout(displayID: "display", spaceID: "2").id == old, "Other Spaces retain their layouts")
        expect(library.displayBindings["display"] == fallback, "A Space-only choice does not change the display fallback")
        let restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        expect(restored.layout(displayID: "display", spaceID: "1").id == next, "The chosen Space layout survives a relaunch")
        library.preferences.perSpace = false
        library.assignLayout(next, displayID: "display", spaceID: "1")
        expect(library.layout(displayID: "display", spaceID: "2").id == next, "Display-wide mode ignores retained Space assignments")
        library.preferences.perSpace = true
        library.assignLayout(next, displayID: "second", spaceID: "")
        expect(library.displayBindings["second"] == next && library.spaceBindings["second:"] == nil, "Unknown Space falls back to display assignment")
        library.spaceBindings["display:3"] = UUID()
        expect(library.layout(displayID: "display", spaceID: "3").id == next, "A stale Space layout falls back to the valid display layout")
        library.assignLayout(UUID(), displayID: "display", spaceID: "1")
        expect(library.layout(displayID: "display", spaceID: "1").id == next, "Unknown layout IDs cannot replace an active assignment")
        print("\(checks-failures)/\(checks) layout selection checks passed")
        if failures > 0 { exit(1) }
    }
}
