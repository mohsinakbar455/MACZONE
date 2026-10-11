import AppKit

/// Geometry and z-order only; no window names, screenshots or screen-recording
/// permission. Reading these bounds does not wait for the target app's UI loop.
enum WindowServerSnapshot {
    struct Window { let id: UInt32; let pid: pid_t; let frame: CGRect }
    static func frame(id: UInt32) -> CGRect? {
        guard let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let row = rows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }) else { return nil }
        return bounds(row)
    }
    static func window(at point: CGPoint) -> Window? {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for row in rows {
            guard (row[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let frame = bounds(row), frame.contains(point),
                  let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { continue }
            // Do not look through a menu, dialog or another front window and
            // accidentally choose a background document instead.
            return Window(id: id, pid: pid, frame: frame)
        }
        return nil
    }
    static func visibleWindows() -> [Window] {
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard (row[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let frame = bounds(row), let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
            return Window(id: id, pid: pid, frame: frame)
        }
    }
    private static func bounds(_ row: [String: Any]) -> CGRect? {
        guard let value = row[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: value), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }
}
