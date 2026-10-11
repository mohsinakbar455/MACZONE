// MACZONE native workspace, 2026-10-08. GPL-3.0.
import SwiftUI
import AppKit

struct WorkspaceView: View {
    @ObservedObject var store = AppStore.shared
    @Environment(\.colorScheme) private var scheme
    private let navigation: [(String, String, String)] = [
        ("layouts", "Layouts", "layout-grid"), ("profiles", "Displays", "monitor"),
        ("spaces", "Spaces", "layers"), ("sessions", "Sessions", "history"),
        ("apps", "App Rules", "app-window")
    ]
    var body: some View {
        GeometryReader { window in
            workspace.frame(width: window.size.width, height: window.size.height)
        }
        .tint(scheme == .dark ? Brand.yellow : Brand.navy)
        .preferredColorScheme(store.library.preferences.appearance == "system" ? nil : store.library.preferences.appearance == "dark" ? .dark : .light)
        .frame(minWidth: 980, minHeight: 660)
        .alert("MACZONE", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var workspace: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    BrandMark().frame(width: 32, height: 32)
                    Text("MACZONE").font(.system(size: 14, weight: .bold)).tracking(0.8).fixedSize()
                    Spacer(minLength: 0)
                }.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 32)
                List(selection: $store.selection) {
                    Section("Workspace") {
                        ForEach(navigation, id: \.0) { item in navRow(item) }
                    }
                    Section("Preferences") {
                        ForEach(SettingsSection.all) { section in
                            navRow((section.id, section.title, section.icon))
                        }
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                    .onChange(of: store.selection) { _, selection in
                        if SettingsSection.all.contains(where: { $0.id == selection }) { store.settingsSelection = selection }
                    }
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        Circle().fill(store.library.preferences.enabled ? Brand.yellow : Color.secondary).frame(width: 6, height: 6)
                        Text(!store.library.preferences.enabled ? "Paused" : store.permission ? "Ready to snap" : "Permission needed").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button { store.library.preferences.enabled.toggle() } label: { Lucide(name: store.library.preferences.enabled ? "pause" : "play", size: 13) }.buttonStyle(.plain).help("Pause or resume window management")
                    }
                    if !store.permission {
                        Button { MACZONEDelegate.current?.showWorkspace("permissions") } label: {
                            IconLabel("Enable Accessibility", "shield-check").font(.system(size: 11))
                        }.buttonStyle(.plain).foregroundStyle(scheme == .dark ? Brand.yellow : Brand.navy)
                    }
                }.padding(20)
            }.frame(minWidth: 204, idealWidth: 204, maxWidth: 224)
                .navigationSplitViewColumnWidth(min: 204, ideal: 204, max: 224)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            GeometryReader { available in
            Group {
                switch store.selection {
                case "layouts": LayoutWorkspace()
                case "profiles": ProfilesPage()
                case "spaces": SpacesPage()
                case "sessions": SessionsPage()
                case "apps": AppRulesPage()
                case "general": GeneralPage().frame(maxWidth: .infinity, maxHeight: .infinity)
                case "appearance": AppearancePage().frame(maxWidth: .infinity, maxHeight: .infinity)
                case "shortcuts": ShortcutsPage().frame(maxWidth: .infinity, maxHeight: .infinity)
                case "permissions": PermissionsPage().frame(maxWidth: .infinity, maxHeight: .infinity)
                case "diagnostics": DiagnosticsPage().frame(maxWidth: .infinity, maxHeight: .infinity)
                default: LayoutWorkspace()
                }
            }
            // Every page receives the window's finite content proposal. An
            // oversized page must never move the shared sidebar or titlebar.
            .frame(width: available.size.width, height: available.size.height, alignment: .topLeading)
            .clipped()
            }
            .background { WorkspaceSurface() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Import Layouts…", action: store.importLayouts)
                        Button("Export Layouts…", action: store.exportLayouts)
                        Button("Gather Stray Windows") { WindowEngine.shared.perform("gather") }
                        Divider()
                        Button("Undo", action: store.undo).keyboardShortcut("z")
                        Button("Redo", action: store.redo).keyboardShortcut("z", modifiers: [.command, .shift])
                    } label: {
                        Lucide(name: "ellipsis").foregroundStyle(Color.primary).padding(.horizontal, 8).frame(height: 24)
                    }
                    .menuIndicator(.hidden).fixedSize()
                    .help("Workspace actions").accessibilityLabel("Workspace actions")
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = store.notice {
                    HStack(spacing: 9) { Lucide(name: "check", size: 14).foregroundStyle(Brand.yellow); Text(notice).font(.system(size: 12)).lineLimit(3) }
                        .padding(.horizontal, 18).padding(.vertical, 12).glassEffect(.regular, in: Capsule()).padding(20).allowsHitTesting(false)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
    private func navRow(_ item: (String, String, String)) -> some View {
        HStack(spacing: 10) {
            Lucide(name: item.2, size: 16).foregroundStyle(store.selection == item.0 ? (scheme == .dark ? Brand.yellow : Brand.navy) : .secondary)
            Text(item.1).font(.system(size: 13, weight: store.selection == item.0 ? .semibold : .regular)).foregroundStyle(Color.primary)
        }.padding(.vertical, 6).tag(item.0)
    }
}

struct LayoutWorkspace: View {
    @ObservedObject var store = AppStore.shared
    @ViewState private var snapToGrid = true
    @AppStorage("showZoneInspector") private var showInspector = true
    @ViewState private var showHelp = false
    var body: some View {
        GeometryReader { available in
            content.frame(width: available.size.width, height: available.size.height, alignment: .top)
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                PageHeading(title: "Layouts", subtitle: "")
                Spacer()
                Menu {
                    Button("Blank Layout") { store.addLayout() }
                    Divider()
                    ForEach(ZoneLayout.presets) { preset in Button(preset.name) { store.addLayout(preset) } }
                } label: { IconLabel("New Layout", "plus").foregroundStyle(Brand.black) }
                    .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Brand.yellow, in: Capsule()).foregroundStyle(Brand.black).tint(Brand.black).fontWeight(.semibold)
            }.padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 16)
            HStack(spacing: 14) {
                HStack(spacing: 8) { Lucide(name: "monitor", size: 15); Picker("Display", selection: $store.selectedDisplayID) { ForEach(store.displays) { Text($0.name).tag($0.id) } }.labelsHidden().fixedSize() }
                if let display = store.selectedDisplay {
                    Text(display.resolution).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Using \(store.layout(for: display).name)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 32).padding(.bottom, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(store.library.layouts) { layout in
                        Button { store.selectedLayoutID = layout.id; store.selectedZoneID = layout.zones.first?.id } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                LayoutThumbnail(layout: layout, selected: layout.id == store.selectedLayoutID).frame(width: 116, height: 66)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(layout.id == store.selectedLayoutID ? Brand.yellow : Color.clear, lineWidth: 2))
                                Text(layout.name).font(.system(size: 11, weight: layout.id == store.selectedLayoutID ? .semibold : .regular)).lineLimit(1).frame(width: 116, alignment: .leading)
                            }.padding(3)
                        }.buttonStyle(.plain).accessibilityLabel("Edit \(layout.name), \(layout.zones.count) zones")
                            .contextMenu {
                                Button("Rename…") { presentNameSheet(title: "Rename Layout", defaultValue: layout.name) { var copy = layout; copy.name = $0; store.editCheckpoint(); store.updateLayout(copy) } }
                                Button("Duplicate") { store.addLayout(layout) }
                                Button("Delete", role: .destructive) { confirmDelete("Delete \(layout.name)?") { store.deleteLayout(layout.id) } }.disabled(store.library.layouts.count == 1)
                            }
                    }
                }.padding(.horizontal, 32).padding(.vertical, 4)
            }.frame(height: 100)
            Divider().padding(.top, 16)
            if let layout = store.selectedLayout {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(layout.name).font(.system(size: 15, weight: .semibold))
                            Text("\(layout.zones.count) zones").font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Toggle("Snap to grid", isOn: $snapToGrid).toggleStyle(.checkbox).font(.system(size: 11))
                            ToolButton(title: showInspector ? "Hide inspector" : "Show inspector", icon: "sliders-horizontal") { showInspector.toggle() }
                        }
                        GeometryReader { canvas in
                            ZoneCanvas(layout: layout, snapToGrid: snapToGrid)
                                .id(layout.id)
                                .aspectRatio(min(2.6, max(1.4, (store.selectedDisplay?.screen.frame.width ?? 1920) / (store.selectedDisplay?.screen.frame.height ?? 1080))), contentMode: .fit)
                                .frame(width: canvas.size.width, height: canvas.size.height)
                        }.frame(minHeight: 100).layoutPriority(-1)
                        HStack {
                            Button { store.addZone() } label: { IconLabel("Add Zone", "plus") }.buttonStyle(ReadableGlassButtonStyle())
                            ToolButton(title: "Duplicate zone", icon: "copy", action: store.duplicateZone).disabled(store.selectedZoneID == nil)
                            ToolButton(title: "Delete zone", icon: "trash-2", action: store.deleteZone).disabled(store.selectedZoneID == nil || layout.zones.count < 2)
                            Spacer()
                            ToolButton(title: "Editing help", icon: "circle-help") { showHelp.toggle() }
                                .popover(isPresented: $showHelp) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Shape your layout").font(.headline)
                                        Text("Drag a zone to move it. Pull any edge or corner to resize.")
                                        Text("Arrow keys nudge. Option + arrow keys resize. Escape cancels a drag.")
                                        Divider()
                                        Text("Hold \(store.library.preferences.snapKey.rawValue) while dragging an app window to snap. Add \(store.library.preferences.spanKey.rawValue) to span zones.")
                                    }.font(.system(size: 12)).padding(22).frame(width: 310)
                                }
                            Button { WindowEngine.shared.preview(layout: layout) } label: { IconLabel("Preview", "eye") }.buttonStyle(ReadableGlassButtonStyle())
                        }.controlSize(.regular)
                    }.padding(28).frame(minWidth: 410, maxWidth: .infinity, maxHeight: .infinity)
                    if showInspector {
                        Divider()
                        ZoneInspector().frame(width: 216).frame(maxHeight: .infinity)
                    }
                }
            }
            Divider()
            HStack {
                Text("Edits save automatically").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                PrimaryButton(title: "Apply to Display", icon: "check", action: store.applyLayout)
            }.padding(.horizontal, 28).padding(.vertical, 16)
        }
    }
}

struct ZoneCanvas: View {
    @ObservedObject var store = AppStore.shared
    let layout: ZoneLayout
    let snapToGrid: Bool
    @ViewState private var dragStart: Zone?
    @ViewState private var dragHandle: ZoneHandle = .move
    @ViewState private var draft: Zone?
    @ViewState private var cancelled = false
    @FocusState private var focused: Bool
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(Brand.black)
                Canvas { context, size in
                    for x in stride(from: 16.0, to: size.width, by: 20) { for y in stride(from: 16.0, to: size.height, by: 20) { context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(Brand.ice.opacity(0.12))) } }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
                ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, savedZone in
                    let zone = draft?.id == savedZone.id ? draft! : savedZone
                    let selected = store.selectedZoneID == zone.id
                    let size = CGSize(width: max(12, zone.width * proxy.size.width - 8), height: max(12, zone.height * proxy.size.height - 8))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Brand.yellow.opacity(0.15) : Brand.navy.opacity(0.82))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Brand.yellow : Brand.ice.opacity(0.18), lineWidth: selected ? 2 : 1))
                        .overlay {
                            VStack(spacing: 9) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 28, weight: .medium, design: .rounded)).foregroundStyle(selected ? Brand.yellow : Brand.ice)
                                if size.width > 90 { Text(zone.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.ice).lineLimit(1) }
                                if selected && size.width > 110 { Text("\(Int(zone.width*100))% × \(Int(zone.height*100))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(Brand.ice.opacity(0.75)) }
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .overlay {
                            if selected {
                                Canvas { context, bounds in
                                    for point in [CGPoint(x: 4, y: 4), CGPoint(x: bounds.width/2, y: 4), CGPoint(x: bounds.width-4, y: 4), CGPoint(x: 4, y: bounds.height/2), CGPoint(x: bounds.width-4, y: bounds.height/2), CGPoint(x: 4, y: bounds.height-4), CGPoint(x: bounds.width/2, y: bounds.height-4), CGPoint(x: bounds.width-4, y: bounds.height-4)] {
                                        context.fill(Path(roundedRect: CGRect(x: point.x-3, y: point.y-3, width: 6, height: 6), cornerRadius: 2), with: .color(Brand.yellow))
                                    }
                                }.allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                        .offset(x: zone.x*proxy.size.width+4, y: zone.y*proxy.size.height+4)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Zone \(index+1), \(zone.name), \(Int(zone.width*100)) percent wide, \(Int(zone.height*100)) percent high")
                        .accessibilityAddTraits(.isButton).accessibilityAction { store.selectedZoneID = zone.id; focused = true }
                }
            }
                .contentShape(Rectangle()).coordinateSpace(name: layout.id)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(layout.id))
                    .onChanged { value in
                        guard !cancelled else { return }
                        if dragStart == nil {
                            guard let (zone, handle) = ZoneEditing.hit(value.startLocation, zones: layout.zones, canvas: proxy.size) else { return }
                            dragStart = zone; dragHandle = handle
                            store.selectedZoneID = zone.id; focused = true
                            cursor(handle, dragging: true).set()
                        }
                        guard let original = dragStart else { return }
                        // Local continuous preview: no global publication, disk
                        // save, inspector rebuild, or undo entry per mouse event.
                        draft = ZoneEditing.adjusted(original, handle: dragHandle, translation: value.translation, canvas: proxy.size, snap: false)
                    }.onEnded { value in
                        if !cancelled, let original = dragStart,
                           hypot(value.translation.width, value.translation.height) >= 1 {
                            let final = ZoneEditing.adjusted(original, handle: dragHandle, translation: value.translation, canvas: proxy.size, snap: snapToGrid)
                            if final != original { store.editCheckpoint(); store.updateZone(final) }
                        }
                        dragStart = nil; draft = nil; cancelled = false; NSCursor.arrow.set()
                    })
                .onContinuousHover { phase in
                    guard dragStart == nil else { return }
                    switch phase {
                    case let .active(point):
                        if let (_, handle) = ZoneEditing.hit(point, zones: layout.zones, canvas: proxy.size) { cursor(handle).set() }
                        else { NSCursor.arrow.set() }
                    case .ended: NSCursor.arrow.set()
                    }
                }
                .focusable().focused($focused)
                .onKeyPress(.escape) {
                    guard dragStart != nil else { return .ignored }
                    cancelled = true; draft = nil; NSCursor.arrow.set(); return .handled
                }
                .onChange(of: focused) { _, value in if value && store.selectedZoneID == nil { store.selectedZoneID = layout.zones.first?.id } }
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete, .tab]) { press in
                    if press.key == .tab {
                        let index = layout.zones.firstIndex { $0.id == store.selectedZoneID } ?? -1
                        let next = index + (press.modifiers.contains(.shift) ? -1 : 1)
                        guard layout.zones.indices.contains(next) else { return .ignored }
                        store.selectedZoneID = layout.zones[next].id; return .handled
                    }
                    guard var zone = layout.zones.first(where: { $0.id == store.selectedZoneID }) else { store.selectedZoneID = layout.zones.first?.id; return .handled }
                    if press.key == .delete { store.deleteZone(); return .handled }
                    store.editCheckpoint()
                    let step = press.modifiers.contains(.command) ? 0.01 : press.modifiers.contains(.shift) ? 0.005 : 0.001
                    if press.modifiers.contains(.option) {
                        if press.key == .leftArrow { zone.width -= step }; if press.key == .rightArrow { zone.width += step }
                        if press.key == .upArrow { zone.height -= step }; if press.key == .downArrow { zone.height += step }
                    } else {
                        if press.key == .leftArrow { zone.x -= step }; if press.key == .rightArrow { zone.x += step }
                        if press.key == .upArrow { zone.y -= step }; if press.key == .downArrow { zone.y += step }
                    }
                    store.updateZone(zone); return .handled
                }
        }
    }
    private func cursor(_ handle: ZoneHandle, dragging: Bool = false) -> NSCursor {
        switch handle {
        case .move: return dragging ? .closedHand : .openHand
        case .left: return .frameResize(position: .left, directions: .all)
        case .right: return .frameResize(position: .right, directions: .all)
        case .top: return .frameResize(position: .top, directions: .all)
        case .bottom: return .frameResize(position: .bottom, directions: .all)
        case .topLeft: return .frameResize(position: .topLeft, directions: .all)
        case .topRight: return .frameResize(position: .topRight, directions: .all)
        case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        }
    }
}

struct ZoneInspector: View {
    @ObservedObject var store = AppStore.shared
    private var zone: Zone? { store.selectedLayout?.zones.first { $0.id == store.selectedZoneID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Inspector").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if let layout = store.selectedLayout {
                    Picker("Zone", selection: $store.selectedZoneID) {
                        Text("Select a Zone").tag(UUID?.none)
                        ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in Text("\(index+1). \(zone.name)").tag(Optional(zone.id)) }
                    }.labelsHidden().accessibilityLabel("Select zone to edit")
                }
                if let zone {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Zone name").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField("Name", text: Binding(get: { self.zone?.name ?? "" }, set: { value in var z = zone; z.name = value; store.updateZone(z) })).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Position & size").font(.system(size: 12, weight: .medium))
                        HStack { numberField("X", \.x); numberField("Y", \.y) }
                        HStack { numberField("Width", \.width); numberField("Height", \.height) }
                        Text("Values in percent").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        Lucide(name: "scan-line", size: 27).foregroundStyle(.secondary)
                        Text("Select a zone").font(.system(size: 13, weight: .medium))
                        Text("Choose a zone to edit its size and position.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 13) {
                    Text("Spacing").font(.system(size: 12, weight: .medium))
                    spacingSlider("Between zones", value: $store.library.preferences.gap, range: 0...40)
                    spacingSlider("Screen margin", value: $store.library.preferences.margin, range: 0...60)
                }
            }.padding(20)
        }.background(.primary.opacity(0.025))
    }
    private func numberField(_ title: String, _ key: WritableKeyPath<Zone, Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(title, value: Binding(get: { (zone?[keyPath: key] ?? 0)*100 }, set: { value in guard var z = zone else { return }; store.editCheckpoint(); z[keyPath: key] = value/100; store.updateZone(z) }), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
        }
    }
    private func spacingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue)) pt").monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 10))
            SmoothSlider(title: title, value: value, range: range).controlSize(.small)
        }
    }
}
