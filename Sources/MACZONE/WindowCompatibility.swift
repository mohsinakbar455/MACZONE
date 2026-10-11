import Foundation

/// The eligibility gate shared by pointer lookup, shortcuts and window lists.
enum WindowCompatibility {
    static func accepts(role: String?, subrole: String?, minimized: Bool,
                        registered: Bool = false, movable: Bool = false, resizable: Bool = false) -> Bool {
        guard !minimized else { return false }
        if role == "AXWindow" && subrole == "AXStandardWindow" { return true }
        // Some cross-platform apps expose their actual windows as layout areas
        // or omit the usual subrole. Capability checks alone are insufficient:
        // a docked panel can also advertise a position and size.
        return registered && movable && resizable &&
            (role == "AXWindow" || role == "AXLayoutArea" || role == "AXUnknown")
    }
}
