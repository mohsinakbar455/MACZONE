// MACZONE settings, 2026-10-08. GPL-3.0.
import SwiftUI
import AppKit
import ServiceManagement

struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    static let all = [
        SettingsSection(id: "general", title: "General", icon: "sliders-horizontal"),
        SettingsSection(id: "appearance", title: "Appearance", icon: "palette"),
        SettingsSection(id: "shortcuts", title: "Shortcuts", icon: "keyboard"),
        SettingsSection(id: "permissions", title: "Permissions", icon: "shield-check"),
        SettingsSection(id: "diagnostics", title: "About", icon: "circle-help")
    ]
}

struct SettingsPage<Content: View>: View {
    let title: String; let subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PageHeading(title: title, subtitle: subtitle).padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 8)
            Form { content }.formStyle(.grouped).scrollContentBackground(.hidden)
        }.frame(maxWidth: 780, maxHeight: .infinity, alignment: .topLeading).frame(maxWidth: .infinity)
    }
}

struct GeneralPage: View {
    @ObservedObject var store = AppStore.shared
    @ViewState private var login = SMAppService.mainApp.status == .enabled
    var body: some View {
        SettingsPage(title: "General", subtitle: "") {
            Section("Startup") {
                Toggle("Launch MACZONE at login", isOn: $login).onChange(of: login) { _, value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { store.error = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
                }
            }
            Section {
                if !store.permission {
                    Button { MACZONEDelegate.current?.showWorkspace("permissions") } label: { IconLabel("Enable Accessibility to snap windows", "shield-check") }.buttonStyle(.link)
                }
                Picker("Reveal zones while dragging", selection: Binding(get: { store.library.preferences.snapKey }, set: { store.library.preferences.setSnapKey($0) })) {
                    ForEach(SnapModifier.allCases, id: \.self) { Text("\($0.symbol)  \($0.rawValue)").tag($0) }
                }.accessibilityLabel("Snap modifier")
                Picker("Combine adjacent zones", selection: Binding(get: { store.library.preferences.spanKey }, set: { store.library.preferences.setSpanKey($0) })) {
                    ForEach(SnapModifier.allCases, id: \.self) { Text("\($0.symbol)  \($0.rawValue)").tag($0) }
                }.accessibilityLabel("Span modifier")
                Toggle("Snap to screen edges", isOn: $store.library.preferences.edgeSnap)
                    .help("Drag to an edge or corner to fill, halve, or quarter the display without a modifier.")
            } header: { Text("Snap modifiers") } footer: {
                Text("Hold the first key to reveal zones. Add the second to span them. Choosing an occupied key swaps the two.")
            }
            Section {
                Toggle("Show yellow window dividers", isOn: $store.library.preferences.seamResize)
            } header: { Text("Shared edges") } footer: {
                Text("Drag a divider to resize both windows. Click it to swap their places.")
            }
        }
    }
}

struct AppearancePage: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "") {
            Section("Window theme") {
                Picker("Theme", selection: $store.library.preferences.appearance) { Text("Match System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
            }
            Section("Zone overlay") {
                Toggle("Show zone numbers", isOn: $store.library.preferences.showNumbers)
                HStack { Text("Opacity"); SmoothSlider(title: "Overlay opacity", value: $store.library.preferences.overlayOpacity, range: 0.1...0.7, increment: 0.01, unit: "percent"); Text("\(Int((store.library.preferences.overlayOpacity*100).rounded()))%").monospacedDigit().frame(width: 40) }
                Button("Preview on Display") { WindowEngine.shared.preview() }
            }
        }
    }
}

struct PermissionsPage: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(title: "Permissions", subtitle: "")
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Lucide(name: "shield-check", size: 28).foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility").font(.system(size: 17, weight: .semibold))
                        Text(store.permission ? "Connected" : "Permission needed").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.permission { Lucide(name: "check", size: 20) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.permission ? "MACZONE can move and resize your windows." : "Enable MACZONE in System Settings → Privacy & Security → \(store.accessibilityPaneName).")
                        .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        PrimaryButton(title: "Open System Settings", icon: "arrow-up-right", action: store.openAccessibilitySettings)
                        Button { store.permission = AXIsProcessTrusted(); store.toast(store.permission ? "Accessibility connected" : "Permission is not enabled yet") } label: { Text("Recheck") }.buttonStyle(ReadableGlassButtonStyle())
                    }.padding(.top, 8)
                    if !store.permission {
                        DisclosureGroup("Troubleshooting") {
                            Text("After rebuilding, macOS may need a fresh grant. Switch MACZONE off and on, then reopen it. If it is missing or still disconnected, add this build with the + button.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                            Button("Show MACZONE in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }.buttonStyle(.link).padding(.top, 6)
                        }
                    }
                }
            }.padding(26).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            Text("Local to your Mac. No account, screenshots, or window contents collected.").font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(30).frame(maxWidth: 740, alignment: .topLeading).frame(maxWidth: .infinity)
        }
    }
}

struct ShortcutsPage: View {
    @ObservedObject var store = AppStore.shared
    @ViewState private var search = ""
    @ViewState private var boundOnly = false
    @ViewState private var recording: String?
    @AppStorage("collapsedShortcutGroups") private var collapsedGroups = ""
    var filtered: [WindowCommand] { store.commands.filter { (!boundOnly || !store.binding(for: $0).isEmpty) && (search.isEmpty || "\($0.title) \($0.group) \(layoutName(for: $0)) \(store.binding(for: $0))".localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { PageHeading(title: "Shortcuts", subtitle: ""); Button("Reset Defaults") { store.library.shortcuts = [:]; WindowEngine.shared.registerHotkeys() }.buttonStyle(ReadableGlassButtonStyle()) }
            HStack {
                HStack { Lucide(name: "search", size: 15).foregroundStyle(.secondary); TextField("Search actions or shortcuts", text: $search).textFieldStyle(.plain) }.padding(10).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                Toggle("Assigned only", isOn: $boundOnly).toggleStyle(.checkbox).fixedSize()
            }
            if !store.shortcutFailures.isEmpty {
                Text("These shortcuts are used by another app: \(store.shortcutFailures.joined(separator: ", ")). Record a different binding.").font(.system(size: 12)).foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(Set(filtered.map(\.group))).sorted { a, b in a == "Layout Shortcuts" ? b != a : b == "Layout Shortcuts" ? false : a < b }, id: \.self) { group in
                        DisclosureGroup(isExpanded: Binding(get: { !search.isEmpty || !collapsedGroups.components(separatedBy: "|").contains(group) }, set: { expanded in
                            var groups = Set(collapsedGroups.components(separatedBy: "|").filter { !$0.isEmpty })
                            if expanded { groups.remove(group) } else { groups.insert(group) }
                            collapsedGroups = groups.sorted().joined(separator: "|")
                        })) {
                            if group == "Layout Shortcuts" {
                                Text("Choose up to six layouts. Cycle follows 01–06, skips empty slots, and previews each change for two seconds.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
                            }
                            ForEach(filtered.filter { $0.group == group }.sorted { a, b in
                                if group == "Layout Shortcuts" { return a.id == "layout.cycle" ? false : b.id == "layout.cycle" ? true : a.id < b.id }
                                return false
                            }) { command in
                                HStack {
                                    Text(command.title).font(.system(size: 12))
                                    if let slot = slot(for: command) {
                                        Picker(command.title, selection: Binding(get: { store.library.layoutShortcutSlots?[String(slot)] }, set: { store.library.setShortcutLayout($0, slot: slot) })) {
                                            Text("Not assigned").tag(UUID?.none)
                                            if let id = store.library.layoutShortcutSlots?[String(slot)], !store.library.layouts.contains(where: { $0.id == id }) {
                                                Text("Layout removed").tag(Optional(id))
                                            }
                                            ForEach(store.library.layouts) { Text($0.name).tag(Optional($0.id)) }
                                        }.labelsHidden().frame(maxWidth: 220).help("Choose the saved layout for this slot")
                                    }
                                    Spacer()
                                    Button { recording = command.id } label: {
                                        Text(recording == command.id ? "Press shortcut…" : chord(store.binding(for: command)))
                                            .font(.system(size: 12, weight: .medium, design: .monospaced)).frame(minWidth: 104).padding(.horizontal, 9).padding(.vertical, 7)
                                            .background(recording == command.id ? Brand.yellow : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                                            .foregroundStyle(recording == command.id ? Brand.black : Color.primary)
                                    }.buttonStyle(.plain).accessibilityLabel("Record shortcut for \(command.title)")
                                    Button { store.library.shortcuts[command.id] = ""; WindowEngine.shared.registerHotkeys() } label: { Lucide(name: "x", size: 12) }.buttonStyle(.plain).help("Clear shortcut").disabled(store.binding(for: command).isEmpty)
                                }.padding(.vertical, 7)
                                Divider()
                            }
                        } label: { Text(group).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
                    }
                }.padding(.vertical, 5)
            }
            if filtered.isEmpty { Text("No matching shortcuts").foregroundStyle(.secondary).frame(maxWidth: .infinity) }
        }.padding(30)
        .background(ShortcutRecorder(active: recording != nil) { value in
            guard let id = recording else { return }
            recording = nil
            guard let value else { return }
            let key = GlobalHotkey.parseShortcut(value)
            if let collision = store.commands.first(where: { c in let p = GlobalHotkey.parseShortcut(store.binding(for: c)); return c.id != id && p.keyCode == key.keyCode && p.modifiers == key.modifiers }) {
                store.error = "This shortcut is already assigned to \(collision.title). Clear that binding first."; return
            }
            store.library.shortcuts[id] = value; WindowEngine.shared.registerHotkeys()
        }.frame(width: 0, height: 0))
    }
    private func slot(for command: WindowCommand) -> Int? {
        command.id.hasPrefix("layout.slot.") ? Int(command.id.dropFirst(12)) : nil
    }
    private func layoutName(for command: WindowCommand) -> String {
        slot(for: command).flatMap { store.library.shortcutLayout($0)?.name } ?? ""
    }
    private func chord(_ raw: String) -> String {
        if raw.isEmpty { return "Record" }
        return raw.replacingOccurrences(of: "Control+", with: "⌃").replacingOccurrences(of: "Option+", with: "⌥").replacingOccurrences(of: "Shift+", with: "⇧").replacingOccurrences(of: "Command+", with: "⌘").replacingOccurrences(of: "Left", with: "←").replacingOccurrences(of: "Right", with: "→").replacingOccurrences(of: "Up", with: "↑").replacingOccurrences(of: "Down", with: "↓").replacingOccurrences(of: "Delete", with: "⌫")
    }
}


struct DiagnosticsPage: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        SettingsPage(title: "About", subtitle: "") {
            Section("Application") {
                HStack(spacing: 18) { BrandMark().frame(width: 52, height: 52); VStack(alignment: .leading, spacing: 6) { Text("MACZONE").font(.title2.bold()); Text("Version 0.1.0 · Development build").font(.system(size: 12)).foregroundStyle(.secondary) } }.padding(.vertical, 8)
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("Connected displays", value: "\(store.displays.count)")
                LabeledContent("Accessibility", value: store.permission ? "Granted" : "Not granted")
                LabeledContent("Saved layouts", value: "\(store.library.layouts.count)")
                Button("Open Data Folder") { store.save(); NSWorkspace.shared.open(store.directory) }
                Button("Export Diagnostics…", action: exportDiagnostics)
            }
            Section("Open source") {
                Text("Built on MacsyZones by Oğuzhan Eroğlu. MACZONE modifications dated October 8, 2026. Distributed under GNU GPL version 3; source and build instructions are included in this project. No warranty.").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("View GPL-3 License") { if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) { NSWorkspace.shared.open(url) } }
                Text("Icons: Lucide 0.468.0, ISC / MIT. Native controls: SwiftUI and AppKit.").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("View Lucide License") { if let url = Bundle.main.resourceURL?.appendingPathComponent("Lucide/LICENSE") { NSWorkspace.shared.open(url) } }
            }
        }
    }
    private func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MACZONE Diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "MACZONE 0.1.0\n\(ProcessInfo.processInfo.operatingSystemVersionString)\nAccessibility: \(store.permission)\nDisplays: \(store.displays.count)\nLayouts: \(store.library.layouts.count)\nProfiles: \(store.library.profiles.count)\nSessions: \(store.library.sessions.count)\nShortcut conflicts: \(store.shortcutFailures.joined(separator: ", "))\n\nNo window titles, app names, or user files are included.\n"
        do { try text.write(to: url, atomically: true, encoding: .utf8); store.toast("Diagnostics exported") } catch { store.error = error.localizedDescription }
    }
}
