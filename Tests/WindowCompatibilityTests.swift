import Foundation

@main struct WindowCompatibilityTests {
    static func main() {
        // Captured read-only from Premiere 26's AXWindows on 2026-10-08:
        // main window = AXLayoutArea / AXFloatingWindow, position+size settable.
        // Adjacent helper = AXWindow / AXDialog, position only settable.
        let cases: [(String, String, String?, Bool, Bool, Bool, Bool, Bool)] = [
            ("Premiere main window can start a snap", "AXLayoutArea", "AXFloatingWindow", false, true, true, true, true),
            ("Standard windows remain supported", "AXWindow", "AXStandardWindow", false, true, true, true, true),
            ("Unknown custom top-level window", "AXWindow", "AXUnknown", false, true, true, true, true),
            ("Missing subrole with proven capabilities", "AXWindow", nil, false, true, true, true, true),
            ("Fixed-size helper is excluded", "AXWindow", "AXDialog", false, true, true, false, false),
            ("Docked internal panel is not a top-level window", "AXLayoutArea", "AXFloatingWindow", false, false, true, true, false),
            ("Minimized custom window is excluded", "AXLayoutArea", "AXFloatingWindow", true, true, true, true, false),
            ("Non-movable custom window is excluded", "AXLayoutArea", "AXFloatingWindow", false, true, false, true, false)
        ]
        var failures = 0
        for (label, role, subrole, minimized, registered, movable, resizable, expected) in cases {
            let actual = WindowCompatibility.accepts(role: role, subrole: subrole, minimized: minimized,
                                                     registered: registered, movable: movable, resizable: resizable)
            if actual != expected { print("FAIL: \(label)"); failures += 1 }
        }
        print("\(cases.count-failures)/\(cases.count) window compatibility checks passed")
        if failures > 0 { exit(1) }
    }
}
