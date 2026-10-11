// MACZONE library workflows, 2026-10-08. GPL-3.0.
import SwiftUI
import AppKit

struct ProfilesPage: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { PageHeading(title: "Displays", subtitle: "Save a layout setup for each desk."); if !store.library.profiles.isEmpty { PrimaryButton(title: "Save Setup", icon: "plus", action: create) } }
            Toggle("Activate matching profiles when displays change", isOn: $store.library.preferences.autoProfiles).toggleStyle(.checkbox).font(.system(size: 12))
            if store.library.profiles.isEmpty {
                EmptyState(icon: "monitor", title: "Remember this setup", detail: "Save these display assignments and recall them when you reconnect.", button: "Save Setup", action: create)
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach($store.library.profiles) { $profile in
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    Lucide(name: "monitor", size: 21)
                                    TextField("Profile name", text: $profile.name).textFieldStyle(.plain).font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                    if profile.id == store.library.activeProfileID { Text("Active").font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.black).padding(.horizontal, 9).padding(.vertical, 4).background(Brand.yellow, in: Capsule()) }
                                    Button("Activate") { store.activateProfile(profile) }.buttonStyle(ReadableGlassButtonStyle())
                                    Button { confirmDelete("Delete \(profile.name)?") { store.library.profiles.removeAll { $0.id == profile.id }; if store.library.activeProfileID == profile.id { store.library.activeProfileID = nil } } } label: { Lucide(name: "trash-2", size: 15) }.buttonStyle(.plain).help("Delete profile")
                                }
                                ForEach(store.displays) { display in
                                    HStack { Text(display.name).font(.system(size: 12)); Spacer(); Picker("Layout", selection: Binding(get: { profile.bindings[display.id] ?? store.library.layouts[0].id }, set: { profile.bindings[display.id] = $0 })) { ForEach(store.library.layouts) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 180) }
                                }
                                Picker("Restore session on activation", selection: $profile.sessionID) { Text("None").tag(UUID?.none); ForEach(store.library.sessions) { Text($0.name).tag(Optional($0.id)) } }
                            }.padding(22).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                        }
                    }
                }
            }
        }.padding(32)
    }
    private func create() { presentNameSheet(title: "Save Display Profile", defaultValue: "My Setup") { store.createProfile(name: $0) } }
}

struct SessionsPage: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { PageHeading(title: "Sessions", subtitle: "Save and restore your window arrangement."); if !store.library.sessions.isEmpty { PrimaryButton(title: "Save Session", icon: "plus", action: save) } }
            if store.library.sessions.isEmpty {
                EmptyState(icon: "history", title: "Keep your place", detail: "Capture your open windows so you can return to this arrangement.", button: "Save Session", action: save)
            } else {
                List {
                    ForEach(store.library.sessions) { session in
                        HStack(spacing: 18) {
                            Lucide(name: "panels-top-left", size: 28).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) { Text(session.name).font(.system(size: 14, weight: .medium)); Text("\(session.windows.count) windows · \(session.date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer()
                            Button { WindowEngine.shared.restoreSession(session) } label: { IconLabel("Restore", "rotate-ccw") }.buttonStyle(ReadableGlassButtonStyle())
                            Menu {
                                Button("Rename…") { presentNameSheet(title: "Rename Session", defaultValue: session.name) { name in if let i = store.library.sessions.firstIndex(where: { $0.id == session.id }) { store.library.sessions[i].name = name } } }
                                Button("Delete", role: .destructive) { confirmDelete("Delete \(session.name)?") { store.library.sessions.removeAll { $0.id == session.id } } }
                            } label: { Lucide(name: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                        }.padding(.vertical, 14)
                    }
                }.listStyle(.inset).scrollContentBackground(.hidden)
                Text("Restoration matches running apps by window title, then window order. Apps that are closed stay closed.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(32)
    }
    private func save() { presentNameSheet(title: "Save Window Session", defaultValue: Date().formatted(date: .abbreviated, time: .shortened)) { WindowEngine.shared.captureSession(name: $0) } }
}

struct SpacesPage: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        SettingsPage(title: "Spaces", subtitle: "A layout for each Mission Control desktop.") {
            Section {
                Toggle("Switch layouts when the active Space changes", isOn: $store.library.preferences.perSpace)
                Button("Refresh Spaces") { store.refreshSpaces() }
            } footer: { Text("If macOS recreates a desktop, its layout may need reassignment.") }
            ForEach(store.displays) { display in
                Section(display.name) {
                    let spaces = store.spaces.filter { $0.displayID == display.id }
                    if spaces.isEmpty { Text("No desktop information is available for this display.").foregroundStyle(.secondary) }
                    ForEach(spaces, id: \.id) { space in
                        let key = display.id + ":" + space.id
                        Picker(space.name + (space.id == (store.activeSpaces[display.id] ?? store.activeSpace) ? " · Active" : ""), selection: Binding(get: { store.library.spaceBindings[key] }, set: { store.library.spaceBindings[key] = $0 })) {
                            Text("Use Display Default").tag(UUID?.none)
                            ForEach(store.library.layouts) { Text($0.name).tag(Optional($0.id)) }
                        }.disabled(!store.library.preferences.perSpace)
                    }
                }
            }
        }
    }
}

struct AppRulesPage: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { PageHeading(title: "App Rules", subtitle: "Choose where new windows belong."); if !store.library.appRules.isEmpty { PrimaryButton(title: "Add App", icon: "plus", action: addApp) } }
            if store.library.appRules.isEmpty {
                EmptyState(icon: "app-window", title: "Give an app a place", detail: "Send new windows to a zone, or exclude an app from snapping.", button: "Add App", action: addApp)
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach($store.library.appRules) { $rule in
                            VStack(alignment: .leading, spacing: 17) {
                                HStack {
                                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 34, height: 34) }
                                    VStack(alignment: .leading, spacing: 4) { Text(rule.name).font(.system(size: 14, weight: .semibold)); Text(rule.bundleID).font(.system(size: 10)).foregroundStyle(.secondary) }
                                    Spacer()
                                    Button { store.library.appRules.removeAll { $0.id == rule.id } } label: { Lucide(name: "trash-2", size: 15) }.buttonStyle(.plain).help("Remove rule")
                                }
                                Toggle("Skip drag-to-snap", isOn: $rule.skipDrag)
                                Toggle("Automatically place new windows", isOn: $rule.autoPlace)
                                if rule.autoPlace {
                                    HStack(spacing: 16) {
                                        Picker("Display", selection: $rule.displayID) {
                                            Text("Primary Display").tag("")
                                            if !rule.displayID.isEmpty && !store.displays.contains(where: { $0.id == rule.displayID }) {
                                                Text("Disconnected display").tag(rule.displayID)
                                            }
                                            ForEach(store.displays) { Text($0.name).tag($0.id) }
                                        }
                                        Picker("Layout", selection: Binding(get: { rule.layoutID }, set: { id in
                                            if let layout = store.library.layouts.first(where: { $0.id == id }) { rule.selectLayout(layout) }
                                        })) {
                                            if !store.library.layouts.contains(where: { $0.id == rule.layoutID }) {
                                                Text("Choose layout").tag(rule.layoutID)
                                            }
                                            ForEach(store.library.layouts) { Text($0.name).tag(Optional($0.id)) }
                                        }
                                        if let layout = store.library.layouts.first(where: { $0.id == rule.layoutID }) {
                                            Picker("Zone", selection: Binding(get: { rule.zoneID }, set: { id in
                                                rule.zoneID = id
                                                rule.zoneIndex = layout.zones.firstIndex(where: { $0.id == id }) ?? 0
                                            })) {
                                                if !layout.zones.contains(where: { $0.id == rule.zoneID }) { Text("Choose zone").tag(rule.zoneID) }
                                                ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                                                    Text("\(index+1). \(zone.name)").tag(Optional(zone.id))
                                                }
                                            }
                                        }
                                    }.lineLimit(1)
                                    if !rule.displayID.isEmpty && !store.displays.contains(where: { $0.id == rule.displayID }) {
                                        Text("Placement resumes when this display reconnects.").foregroundStyle(.secondary)
                                    } else if !store.library.layouts.contains(where: { $0.id == rule.layoutID && $0.zones.contains(where: { $0.id == rule.zoneID }) }) {
                                        Text("Choose an available layout and zone to resume placement.").foregroundStyle(.secondary)
                                    }
                                }
                            }.font(.system(size: 12)).toggleStyle(.switch).padding(22).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                        }
                    }
                }
            }
        }.padding(32)
    }
    private func addApp() {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        guard !store.library.appRules.contains(where: { $0.bundleID == id }) else { store.toast("This app already has a rule."); return }
        var rule = AppRule(name: url.deletingPathExtension().lastPathComponent, bundleID: id)
        if let display = store.selectedDisplay {
            rule.displayID = display.id
            rule.selectLayout(store.layout(for: display))
        }
        store.library.appRules.append(rule)
    }
}
