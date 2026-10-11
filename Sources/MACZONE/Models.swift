// MACZONE, modified from the MacsyZones foundation, 2026-10-08. GPL-3.0.
import Foundation
import CoreGraphics

struct Zone: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    mutating func constrain() {
        x = min(max(x.isFinite ? x : 0, 0), 0.95)
        y = min(max(y.isFinite ? y : 0, 0), 0.95)
        width = min(max(width.isFinite ? width : 0.5, 0.05), 1 - x)
        height = min(max(height.isFinite ? height : 0.5, 0.05), 1 - y)
    }
}

struct ZoneLayout: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var zones: [Zone]
    var favorite = false
    static func columns(_ count: Int) -> ZoneLayout {
        ZoneLayout(name: "\(count) Columns", zones: (0..<count).map {
            Zone(name: "Column \($0 + 1)", x: Double($0) / Double(count), y: 0, width: 1 / Double(count), height: 1)
        })
    }
    static func grid(rows: Int, columns: Int) -> ZoneLayout {
        ZoneLayout(name: "\(columns) × \(rows) Grid", zones: (0..<(rows * columns)).map {
            Zone(name: "Zone \($0 + 1)", x: Double($0 % columns) / Double(columns), y: Double($0 / columns) / Double(rows), width: 1 / Double(columns), height: 1 / Double(rows))
        })
    }
    static let presets: [ZoneLayout] = [
        .columns(2), .columns(3), .columns(4), .grid(rows: 2, columns: 2),
        ZoneLayout(name: "Focus", zones: [Zone(name: "Main", x: 0, y: 0, width: 0.65, height: 1), Zone(name: "Reference", x: 0.65, y: 0, width: 0.35, height: 0.5), Zone(name: "Tools", x: 0.65, y: 0.5, width: 0.35, height: 0.5)]),
        ZoneLayout(name: "Ultrawide", zones: [Zone(name: "Left", x: 0, y: 0, width: 0.25, height: 1), Zone(name: "Main", x: 0.25, y: 0, width: 0.5, height: 1), Zone(name: "Right", x: 0.75, y: 0, width: 0.25, height: 1)]),
        .grid(rows: 2, columns: 1), .grid(rows: 3, columns: 3)
    ]
}

struct DisplayProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var bindings: [String: UUID]
    var sessionID: UUID?
}

struct WindowRecord: Codable, Identifiable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var title: String
    var index: Int
    var displayID: String
    var frame: CGRect
    var normalizedFrame: CGRect
}

struct WindowSession: Codable, Identifiable {
    var id = UUID()
    var name: String
    var date = Date()
    var windows: [WindowRecord]
}

struct AppRule: Codable, Identifiable {
    var id = UUID()
    var name: String
    var bundleID: String
    var skipDrag = false
    var autoPlace = false
    var displayID = ""
    var zoneIndex = 0
    // Optional fields keep libraries written before explicit rule layouts readable.
    var layoutID: UUID?
    var zoneID: UUID?

    mutating func selectLayout(_ layout: ZoneLayout) {
        layoutID = layout.id
        zoneIndex = 0
        zoneID = layout.zones.first?.id
    }
}

enum SnapModifier: String, CaseIterable {
    case shift = "Shift", option = "Option", control = "Control", command = "Command"
    var symbol: String {
        switch self { case .shift: return "⇧"; case .option: return "⌥"; case .control: return "⌃"; case .command: return "⌘" }
    }
}

enum SnapGesture: Equatable {
    case none, zones(spanning: Bool), edges
}

struct Preferences: Codable {
    var appearance = "system"
    var gap = 10.0
    var margin = 12.0
    var overlayOpacity = 0.28
    var showNumbers = true
    var snapModifier = "Shift"
    var spanModifier = "Option"
    var edgeSnap = false
    var autoProfiles = true
    var perSpace = false
    // Retained for decoding older libraries. MACZONE is now a menu-bar utility.
    var showDock = false
    var seamResize = true
    var enabled = true

    // Keep the existing string-based file format, but resolve keys consistently
    // in the UI and engine, including old files with duplicate/unknown values.
    var snapKey: SnapModifier { SnapModifier(rawValue: snapModifier) ?? .shift }
    var spanKey: SnapModifier {
        let key = SnapModifier(rawValue: spanModifier) ?? .option
        return key != snapKey ? key : (snapKey == .option ? .shift : .option)
    }
    mutating func setSnapKey(_ key: SnapModifier) {
        let previous = snapKey
        let span = spanKey
        snapModifier = key.rawValue
        spanModifier = (key == span ? previous : span).rawValue
    }
    mutating func setSpanKey(_ key: SnapModifier) {
        let previous = spanKey
        let snap = snapKey
        spanModifier = key.rawValue
        snapModifier = (key == snap ? previous : snap).rawValue
    }
    func snapGesture(holding keys: Set<SnapModifier>) -> SnapGesture {
        if keys.contains(snapKey) { return .zones(spanning: keys.contains(spanKey)) }
        return edgeSnap && keys.isEmpty ? .edges : .none
    }
}

struct Library: Codable {
    var schemaVersion = 1
    var layouts = Array(ZoneLayout.presets.prefix(6))
    var displayBindings: [String: UUID] = [:]
    var profiles: [DisplayProfile] = []
    var activeProfileID: UUID?
    var spaceBindings: [String: UUID] = [:]
    var sessions: [WindowSession] = []
    var appRules: [AppRule] = []
    var preferences = Preferences()
    var shortcuts: [String: String] = [:]
    var layoutShortcutSlots: [String: UUID]?

    static let layoutSlotCount = 6
    static func slotCommand(_ slot: Int) -> String { "layout.slot.\(slot)" }

    // Run once on load; store UUIDs rather than indexes so renames/reordering
    // never retarget a user's shortcut. Preserve any extra legacy bindings.
    mutating func migrateLayoutShortcuts() {
        guard layoutShortcutSlots == nil else { return }
        let bound = layouts.filter { !(shortcuts["layout.\($0.id.uuidString)"] ?? "").isEmpty }
        let ordered = bound + layouts.filter { candidate in !bound.contains { $0.id == candidate.id } }
        layoutShortcutSlots = [:]
        for (slot, layout) in ordered.prefix(Self.layoutSlotCount).enumerated() {
            layoutShortcutSlots?[String(slot)] = layout.id
            if let chord = shortcuts.removeValue(forKey: "layout.\(layout.id.uuidString)") {
                shortcuts[Self.slotCommand(slot)] = chord
            }
        }
    }

    func shortcutLayout(_ slot: Int) -> ZoneLayout? {
        guard (0..<Self.layoutSlotCount).contains(slot), let id = layoutShortcutSlots?[String(slot)] else { return nil }
        return layouts.first { $0.id == id }
    }

    mutating func setShortcutLayout(_ id: UUID?, slot: Int) {
        guard (0..<Self.layoutSlotCount).contains(slot), id == nil || layouts.contains(where: { $0.id == id }) else { return }
        migrateLayoutShortcuts()
        // Moving a layout between slots keeps each slot's recorded key intact.
        if let id {
            layoutShortcutSlots = layoutShortcutSlots?.filter { $0.value != id }
        }
        layoutShortcutSlots?[String(slot)] = id
    }

    func nextShortcutLayout(after id: UUID) -> ZoneLayout? {
        let assigned = (0..<Self.layoutSlotCount).compactMap { shortcutLayout($0) }
        guard !assigned.isEmpty else { return nil }
        guard let index = assigned.firstIndex(where: { $0.id == id }) else { return assigned[0] }
        return assigned[(index + 1) % assigned.count]
    }

    func ruleLayout(_ rule: AppRule, displayID: String, spaceID: String) -> ZoneLayout? {
        if let id = rule.layoutID { return layouts.first { $0.id == id } }
        return layout(displayID: displayID, spaceID: spaceID)
    }

    func ruleZone(_ rule: AppRule, displayID: String, spaceID: String) -> Zone? {
        guard let layout = ruleLayout(rule, displayID: displayID, spaceID: spaceID) else { return nil }
        if let id = rule.zoneID { return layout.zones.first { $0.id == id } }
        guard layout.zones.indices.contains(rule.zoneIndex) else { return nil }
        return layout.zones[rule.zoneIndex]
    }

    mutating func pinRuleLayout(at index: Int, displayID: String, spaceID: String) {
        guard appRules.indices.contains(index), appRules[index].layoutID == nil else { return }
        let resolved = layout(displayID: displayID, spaceID: spaceID)
        appRules[index].layoutID = resolved.id
        if resolved.zones.indices.contains(appRules[index].zoneIndex) {
            appRules[index].zoneID = resolved.zones[appRules[index].zoneIndex].id
        }
    }

    func layout(displayID: String, spaceID: String) -> ZoneLayout {
        if preferences.perSpace, let id = spaceBindings[displayID + ":" + spaceID],
           let layout = layouts.first(where: { $0.id == id }) { return layout }
        return layouts.first { $0.id == displayBindings[displayID] } ?? layouts[0]
    }

    mutating func assignLayout(_ id: UUID, displayID: String, spaceID: String) {
        guard layouts.contains(where: { $0.id == id }) else { return }
        if preferences.perSpace && !spaceID.isEmpty {
            spaceBindings[displayID + ":" + spaceID] = id
        } else { displayBindings[displayID] = id }
    }
}

enum ZoneGeometry {
    /// Normalized top-left coordinates converted to Accessibility screen coordinates.
    static func frame(_ zone: Zone, in visible: CGRect, gap: Double, margin: Double) -> CGRect {
        let area = visible.insetBy(dx: margin, dy: margin)
        let left = zone.x <= 0.001 ? 0 : gap / 2
        let top = zone.y <= 0.001 ? 0 : gap / 2
        let right = zone.x + zone.width >= 0.999 ? 0 : gap / 2
        let bottom = zone.y + zone.height >= 0.999 ? 0 : gap / 2
        return CGRect(x: area.minX + zone.x * area.width + left,
                      y: area.minY + zone.y * area.height + top,
                      width: max(40, zone.width * area.width - left - right),
                      height: max(40, zone.height * area.height - top - bottom)).integral
    }
    static func appKitToAX(_ rect: CGRect, primaryHeight: Double) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    static func union(_ zones: [Zone]) -> Zone? {
        guard let first = zones.first else { return nil }
        let r = zones.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        return Zone(name: "Spanned zones", x: r.minX, y: r.minY, width: r.width, height: r.height)
    }
}

struct WindowCommand: Identifiable {
    var id: String
    var title: String
    var group: String
    var shortcut: String
    static var all: [WindowCommand] {
        (1...9).map { WindowCommand(id: "zone.\($0 - 1)", title: "Move to Zone \($0)", group: "Move to Zone", shortcut: "Control+Option+\($0)") } + [
            .init(id: "left", title: "Step Left", group: "Navigate", shortcut: "Control+Option+Left"),
            .init(id: "right", title: "Step Right", group: "Navigate", shortcut: "Control+Option+Right"),
            .init(id: "up", title: "Step Up", group: "Navigate", shortcut: "Control+Option+Up"),
            .init(id: "down", title: "Step Down", group: "Navigate", shortcut: "Control+Option+Down"),
            .init(id: "expand.left", title: "Expand Left", group: "Expand", shortcut: "Control+Option+Shift+Left"),
            .init(id: "expand.right", title: "Expand Right", group: "Expand", shortcut: "Control+Option+Shift+Right"),
            .init(id: "expand.up", title: "Expand Up", group: "Expand", shortcut: "Control+Option+Shift+Up"),
            .init(id: "expand.down", title: "Expand Down", group: "Expand", shortcut: "Control+Option+Shift+Down"),
            .init(id: "shrink.left", title: "Shrink Left", group: "Shrink", shortcut: ""),
            .init(id: "shrink.right", title: "Shrink Right", group: "Shrink", shortcut: ""),
            .init(id: "shrink.up", title: "Shrink Up", group: "Shrink", shortcut: ""),
            .init(id: "shrink.down", title: "Shrink Down", group: "Shrink", shortcut: ""),
            .init(id: "cycle.next", title: "Next Window in Zone", group: "Window", shortcut: "Control+Option+`"),
            .init(id: "cycle.previous", title: "Previous Window in Zone", group: "Window", shortcut: "Control+Option+Shift+`"),
            .init(id: "fill", title: "Fill Display / Restore", group: "Window", shortcut: "Control+Option+F"),
            .init(id: "center", title: "Center on Display", group: "Window", shortcut: "Control+Option+C"),
            .init(id: "height", title: "Maximize Height", group: "Window", shortcut: "Control+Option+H"),
            .init(id: "width", title: "Maximize Width", group: "Window", shortcut: "Control+Option+W"),
            .init(id: "almost", title: "Almost Maximize", group: "Window", shortcut: "Control+Option+M"),
            .init(id: "restore", title: "Restore Last Position", group: "Window", shortcut: "Control+Option+Delete"),
            .init(id: "display.previous", title: "Move to Previous Display", group: "Displays", shortcut: "Control+Option+Command+Left"),
            .init(id: "display.next", title: "Move to Next Display", group: "Displays", shortcut: "Control+Option+Command+Right"),
            .init(id: "layout.cycle", title: "Cycle Layouts 01–06", group: "Layout Shortcuts", shortcut: "Control+Option+L"),
            .init(id: "tile", title: "Tile Visible Windows", group: "Layouts", shortcut: ""),
            .init(id: "half.left", title: "Left Half / Third / Two Thirds", group: "Fractions", shortcut: ""),
            .init(id: "half.right", title: "Right Half / Third / Two Thirds", group: "Fractions", shortcut: ""),
            .init(id: "half.top", title: "Top Half / Third / Two Thirds", group: "Fractions", shortcut: ""),
            .init(id: "half.bottom", title: "Bottom Half / Third / Two Thirds", group: "Fractions", shortcut: ""),
            .init(id: "third.0", title: "First Third", group: "Fractions", shortcut: ""),
            .init(id: "third.1", title: "Center Third", group: "Fractions", shortcut: ""),
            .init(id: "third.2", title: "Last Third", group: "Fractions", shortcut: ""),
            .init(id: "gather", title: "Gather Stray Windows", group: "Window", shortcut: "")
        ]
    }
}
