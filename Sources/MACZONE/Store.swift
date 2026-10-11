// MACZONE — 2026-10-08. GPL-3.0.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DisplayInfo: Identifiable {
    let id: String
    let name: String
    let screen: NSScreen
    var visibleAX: CGRect {
        ZoneGeometry.appKitToAX(screen.visibleFrame, primaryHeight: Double(NSScreen.screens.first?.frame.height ?? 0))
    }
    var resolution: String { "\(Int(screen.frame.width)) × \(Int(screen.frame.height))" }
}

@MainActor final class AppStore: ObservableObject {
    #if MACZONE_UI_QA || MACZONE_LAUNCH_QA
    static let shared = AppStore(directory: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("ui-qa-library"))
    #else
    static let shared = AppStore()
    #endif
    @Published var library: Library { didSet { scheduleSave() } }
    @Published var selection = "layouts"
    @Published var settingsSelection = "general"
    @Published var selectedLayoutID: UUID?
    @Published var selectedZoneID: UUID?
    @Published var selectedDisplayID = ""
    @Published var displays: [DisplayInfo] = []
    @Published var permission = AXIsProcessTrusted()
    @Published var notice: String?
    @Published var error: String?
    @Published var shortcutFailures: [String] = []
    @Published var activeSpace = ""
    @Published var activeSpaces: [String: String] = [:]
    @Published var spaces: [(id: String, name: String, displayID: String)] = []
    private var saveTask: DispatchWorkItem?
    private var undoLayouts: [[ZoneLayout]] = []
    private var redoLayouts: [[ZoneLayout]] = []
    let directory: URL
    var file: URL { directory.appendingPathComponent("library.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MACZONE")
        let url = self.directory.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let loaded = try JSONDecoder().decode(Library.self, from: Data(contentsOf: url))
                guard loaded.schemaVersion == 1, !loaded.layouts.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                library = loaded
            } catch {
                library = Library()
                self.error = "Your library could not be opened. The original file is preserved. Export a copy before replacing it. \(error.localizedDescription)"
                // Use a recovery file until the original library can be recovered.
                self.recoveryMode = true
            }
        } else { library = Library() }
        selectedLayoutID = library.layouts.first?.id
        refreshDisplays(matchProfiles: false)
        library.migrateLayoutShortcuts()
        for index in library.appRules.indices {
            let rule = library.appRules[index]
            if let display = displays.first(where: { $0.id == rule.displayID }) ?? displays.first {
                library.pinRuleLayout(at: index, displayID: display.id, spaceID: activeSpaces[display.id] ?? activeSpace)
            }
        }
    }
    private var recoveryMode = false
    var selectedLayout: ZoneLayout? { library.layouts.first { $0.id == selectedLayoutID } }
    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selectedDisplayID } ?? displays.first }
    var commands: [WindowCommand] {
        WindowCommand.all + (0..<Library.layoutSlotCount).map {
            .init(id: Library.slotCommand($0), title: String(format: "Layout %02d", $0 + 1), group: "Layout Shortcuts", shortcut: "")
        } + library.layouts.filter { !(library.shortcuts["layout.\($0.id.uuidString)"] ?? "").isEmpty }.map {
            .init(id: "layout.\($0.id.uuidString)", title: "Switch to \($0.name)", group: "Additional Layout Shortcuts", shortcut: "")
        }
    }
    func binding(for command: WindowCommand) -> String { library.shortcuts[command.id] ?? command.shortcut }
    var accessibilityPaneName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }
    func openAccessibilitySettings() {
        settingsSelection = "permissions"
        // Opening the pane does not grant permission. Avoid an overlapping TCC
        // prompt; the user controls the grant in System Settings.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        if !NSWorkspace.shared.open(url) {
            error = "System Settings could not be opened. Open it from the Apple menu, then choose Privacy & Security → \(accessibilityPaneName) and enable MACZONE."
        }
    }
    func refreshDisplays(matchProfiles: Bool = true) {
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            let uuid = CGDisplayCreateUUIDFromDisplayID(number).takeRetainedValue()
            let id = CFUUIDCreateString(nil, uuid) as String
            return DisplayInfo(id: id, name: screen.localizedName, screen: screen)
        }
        if !displays.contains(where: { $0.id == selectedDisplayID }) { selectedDisplayID = displays.first?.id ?? "" }
        refreshSpaces()
        if matchProfiles && library.preferences.autoProfiles { matchProfile() }
    }
    func refreshSpaces() {
        spaces = []; activeSpaces = [:]
        let connection = CGSMainConnectionID()
        let active = CGSGetActiveSpace(connection)
        activeSpace = String(active)
        guard let records = CGSCopyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else { return }
        for (displayIndex, record) in records.enumerated() {
            let displayID = record["Display Identifier"] as? String ?? displays[safe: displayIndex]?.id ?? ""
            let resolvedID = displays.contains { $0.id == displayID } ? displayID : displays[safe: displayIndex]?.id ?? displayID
            if let current = record["Current Space"] as? [String: Any], let id = current["ManagedSpaceID"] as? UInt64 { activeSpaces[resolvedID] = String(id) }
            for (index, space) in ((record["Spaces"] as? [[String: Any]]) ?? []).enumerated() {
                guard let id = space["ManagedSpaceID"] as? UInt64 else { continue }
                spaces.append((String(id), "Space \(index + 1)", resolvedID))
            }
        }
    }
    func layout(for display: DisplayInfo) -> ZoneLayout {
        library.layout(displayID: display.id, spaceID: activeSpaces[display.id] ?? activeSpace)
    }
    func assignLayout(_ id: UUID, to display: DisplayInfo) {
        library.assignLayout(id, displayID: display.id, spaceID: activeSpaces[display.id] ?? activeSpace)
    }
    func applyLayout() {
        guard let layout = selectedLayout, let display = selectedDisplay else { return }
        assignLayout(layout.id, to: display)
        toast("\(layout.name) applied to \(display.name)")
    }
    func editCheckpoint() {
        undoLayouts.append(library.layouts)
        if undoLayouts.count > 60 { undoLayouts.removeFirst() }
        redoLayouts.removeAll()
    }
    func undo() {
        guard let previous = undoLayouts.popLast() else { return }
        redoLayouts.append(library.layouts); library.layouts = previous
    }
    func redo() {
        guard let next = redoLayouts.popLast() else { return }
        undoLayouts.append(library.layouts); library.layouts = next
    }
    func updateLayout(_ layout: ZoneLayout) {
        guard let index = library.layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        library.layouts[index] = layout
    }
    func addLayout(_ preset: ZoneLayout? = nil) {
        editCheckpoint()
        var layout = preset ?? ZoneLayout(name: "Untitled Layout", zones: [Zone(name: "Main", x: 0, y: 0, width: 1, height: 1)])
        layout.id = UUID()
        layout.zones = layout.zones.map { var z = $0; z.id = UUID(); return z }
        let base = layout.name
        var n = 2
        while library.layouts.contains(where: { $0.name == layout.name }) { layout.name = "\(base) \(n)"; n += 1 }
        library.layouts.append(layout)
        selectedLayoutID = layout.id; selectedZoneID = nil
    }
    func deleteLayout(_ id: UUID) {
        guard library.layouts.count > 1 else { toast("Keep at least one layout."); return }
        editCheckpoint(); library.layouts.removeAll { $0.id == id }
        library.displayBindings = library.displayBindings.filter { $0.value != id }
        library.spaceBindings = library.spaceBindings.filter { $0.value != id }
        for index in library.profiles.indices { library.profiles[index].bindings = library.profiles[index].bindings.filter { $0.value != id } }
        library.shortcuts.removeValue(forKey: "layout.\(id.uuidString)")
        selectedLayoutID = library.layouts.first?.id
    }
    func updateZone(_ zone: Zone) {
        guard var layout = selectedLayout, let index = layout.zones.firstIndex(where: { $0.id == zone.id }) else { return }
        var z = zone; z.constrain(); layout.zones[index] = z; updateLayout(layout)
    }
    func addZone() {
        guard var layout = selectedLayout else { return }
        editCheckpoint()
        let zone = Zone(name: "Zone \(layout.zones.count + 1)", x: 0.1, y: 0.1, width: 0.4, height: 0.4)
        layout.zones.append(zone); updateLayout(layout); selectedZoneID = zone.id
    }
    func deleteZone() {
        guard var layout = selectedLayout, layout.zones.count > 1 else { return }
        editCheckpoint(); layout.zones.removeAll { $0.id == selectedZoneID }; updateLayout(layout); selectedZoneID = nil
    }
    func duplicateZone() {
        guard var layout = selectedLayout, var zone = layout.zones.first(where: { $0.id == selectedZoneID }) else { return }
        editCheckpoint(); zone.id = UUID(); zone.name += " Copy"; zone.x += 0.03; zone.y += 0.03; zone.constrain()
        layout.zones.append(zone); updateLayout(layout); selectedZoneID = zone.id
    }
    func exportLayouts() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "MACZONE Layouts.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(library.layouts).write(to: url, options: .atomic); toast("Layouts exported") } catch { self.error = error.localizedDescription }
    }
    func importLayouts() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 10_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let layouts = try JSONDecoder().decode([ZoneLayout].self, from: data)
            guard !layouts.isEmpty, layouts.count <= 200, layouts.allSatisfy({ !$0.zones.isEmpty && $0.zones.count <= 100 && $0.zones.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.width.isFinite && $0.height.isFinite } }) else { throw CocoaError(.fileReadCorruptFile) }
            for layout in layouts { var valid = layout; valid.zones = valid.zones.map { var z = $0; z.constrain(); return z }; addLayout(valid) }
            toast("Imported \(layouts.count) layouts")
        } catch { self.error = "Cannot import this file: \(error.localizedDescription)" }
    }
    func createProfile(name: String) {
        let bindings = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, layout(for: $0).id) })
        let profile = DisplayProfile(name: name, bindings: bindings)
        library.profiles.append(profile); library.activeProfileID = profile.id
    }
    func activateProfile(_ profile: DisplayProfile) {
        library.displayBindings.merge(profile.bindings) { _, new in new }; library.activeProfileID = profile.id
        if let id = profile.sessionID, let session = library.sessions.first(where: { $0.id == id }) { WindowEngine.shared.restoreSession(session) }
        toast("\(profile.name) activated")
    }
    func matchProfile() {
        let ids = Set(displays.map(\.id))
        let candidates = library.profiles.filter { !$0.bindings.isEmpty && Set($0.bindings.keys).isSubset(of: ids) }
        let sorted = candidates.sorted { a, b in
            if a.bindings.count == b.bindings.count { return a.id == library.activeProfileID && b.id != library.activeProfileID }
            return a.bindings.count > b.bindings.count
        }
        if let best = sorted.first, best.id != library.activeProfileID { activateProfile(best) }
    }
    func toast(_ message: String) {
        notice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.notice == message { self.notice = nil } }
    }
    func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.save() }
        saveTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let destination = recoveryMode ? directory.appendingPathComponent("library-recovery.json") : file
            try encoder.encode(library).write(to: destination, options: .atomic)
        } catch { self.error = "Your changes could not be saved: \(error.localizedDescription)" }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

func debugLog(_ message: String, file: String = #file, line: Int = #line) { NSLog("MACZONE: %@", message) }
