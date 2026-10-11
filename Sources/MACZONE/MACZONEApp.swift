// MACZONE, 2026-10-08. GPL-3.0.
import SwiftUI
import AppKit

@main enum MACZONEApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = MACZONEDelegate()
        application.delegate = delegate
        #if MACZONE_LAUNCH_QA
        NativeLaunchAudit.start()
        #endif
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class MACZONEDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static weak var current: MACZONEDelegate?
    private var status: NSStatusItem?
    private let popover = NSPopover()
    private var workspace: NSWindow?
    private var settingsKeyMonitor: Any?
    private var popoverGlobalMonitor: Any?
    private var popoverLocalMonitor: Any?
    private var popoverMenuObservers: [NSObjectProtocol] = []
    private var popoverMenus: [NSMenu] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        configureMenus()
        #if MACZONE_UI_QA
        NSApp.setActivationPolicy(.regular)
        AppStore.shared.permission = false
        #else
        NSApp.setActivationPolicy(.accessory)
        #endif
        // Supply the full-color mark explicitly, rather than a template or an
        // automatically synthesized dark icon that erases the yellow field.
        if let url = Bundle.main.url(forResource: "MACZONEYellow", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            NSApp.applicationIconImage = image
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = status?.button {
            let image = NSImage(size: NSSize(width: 19, height: 17), flipped: false) { rect in
                NSColor.labelColor.setStroke()
                let p = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 2, yRadius: 2); p.lineWidth = 1.5; p.stroke()
                let lines = NSBezierPath(); lines.move(to: NSPoint(x: 8, y: 2)); lines.line(to: NSPoint(x: 8, y: 15)); lines.move(to: NSPoint(x: 8, y: 8.5)); lines.line(to: NSPoint(x: 17.5, y: 8.5)); lines.lineWidth = 1.5; lines.stroke(); return true
            }
            image.isTemplate = true; button.image = image; button.toolTip = "MACZONE"; button.target = self; button.action = #selector(togglePopover)
            #if MACZONE_UI_QA
            button.title = " QA"
            #endif
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarView(open: { [weak self] section in self?.popover.performClose(nil); self?.showWorkspace(section) }, close: { [weak self] in self?.popover.performClose(nil) }))
        // Local only: never steal Command-comma from another application's
        // Settings. NSPopover does not reliably route SwiftUI scene commands.
        settingsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.intersection([.command, .option, .shift, .control]) == .command,
                  event.charactersIgnoringModifiers == "," else { return event }
            self.popover.performClose(nil); self.showSettings(); return nil
        }
        #if MACZONE_UI_QA
        // The isolated visual fixture must never install global event monitors
        // or control another application's windows.
        DispatchQueue.main.async { self.showWorkspace() }
        #else
        #if !MACZONE_LAUNCH_QA
        WindowEngine.shared.start()
        #endif
        // No window is created or ordered on launch. There is nothing to hide
        // later, so first launch and restored launches cannot flash the editor.
        #endif
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        // Queue cold-launch requests until applicationDidFinishLaunching has
        // initialized the engine. Alfred opens these URLs in the background.
        for url in urls {
            guard let command = AutomationCommand(url: url) else { continue }
            DispatchQueue.main.async { [weak self] in
                switch command {
                case .cycleLayout: WindowEngine.shared.perform("layout.cycle")
                case .layoutSlot(let slot): WindowEngine.shared.perform(Library.slotCommand(slot))
                case .settings: self?.showWorkspace("shortcuts")
                }
            }
        }
    }
    private func makeWorkspace() -> NSWindow {
        if let workspace { return workspace }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MACZONE"
        window.identifier = NSUserInterfaceItemIdentifier("workspace")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        let hosting = NSHostingController(rootView: WorkspaceView())
        hosting.sceneBridgingOptions = .all
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: 980, height: 660)
        window.center()
        window.setFrameAutosaveName("MACZONEWorkspace")
        workspace = window
        return window
    }
    func showWorkspace(_ section: String = "layouts") {
        if SettingsSection.all.contains(where: { $0.id == section }) {
            AppStore.shared.settingsSelection = section
        }
        AppStore.shared.selection = section
        popover.performClose(nil)
        let window = makeWorkspace()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showSettings() {
        showWorkspace(AppStore.shared.settingsSelection)
    }
    #if MACZONE_UI_QA
    func sizePreview(_ size: NSSize, settings: Bool) {
        if settings { showSettings() } else { showWorkspace("layouts") }
        workspace?.setContentSize(size)
    }
    @objc func showPreviewPopover() {
        workspace?.orderOut(nil)
        togglePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.recordPopoverPreview() }
    }
    private func recordPopoverPreview() {
        guard let view = popover.contentViewController?.view, let window = view.window,
              let screen = window.screen else { return }
        func rect(_ value: NSRect) -> [String: CGFloat] {
            ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
        }
        let report: [String: Any] = [
            "window": rect(window.frame), "content": rect(window.convertToScreen(view.convert(view.bounds, to: nil))),
            "screen": rect(screen.frame), "visibleScreen": rect(screen.visibleFrame),
            "fittingSize": ["width": view.fittingSize.width, "height": view.fittingSize.height],
            "appearance": window.effectiveAppearance.name.rawValue,
            "requestedAppearance": AppStore.shared.library.preferences.appearance,
            "button": status?.button.map { rect($0.window!.convertToScreen($0.convert($0.bounds, to: nil))) } ?? [:]
        ]
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("popover-report.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
    #endif
    @objc private func togglePopover() {
        guard let button = status?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            // Measure the SwiftUI root before AppKit chooses the anchor frame.
            // Otherwise the host grows after showing and its top leaves the screen.
            if let view = popover.contentViewController?.view {
                view.layoutSubtreeIfNeeded()
                let size = view.fittingSize
                popover.contentSize = NSSize(width: ceil(size.width), height: ceil(size.height))
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            monitorPopoverDismissal()
        }
    }
    private func monitorPopoverDismissal() {
        stopPopoverMonitors()
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            popoverMenuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let menu = notification.object as? NSMenu else { return }
                    self.popoverMenus.removeAll { $0 === menu }
                    if notification.name == NSMenu.didBeginTrackingNotification { self.popoverMenus.append(menu) }
                }
            })
        }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Transient popovers in accessory apps can remain visible after another
        // app receives a click, especially after a SwiftUI Picker tracks a menu.
        popoverGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.dismissPopover()
        }
        popoverLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.popover.performClose(nil); return nil }
                return event
            }
            // Let the status button toggle itself, and leave native picker/menu
            // windows alone so selecting a layout does not dismiss its parent.
            let window = event.window
            if window === self.popover.contentViewController?.view.window || window === self.status?.button?.window { return event }
            if let window, window.level.rawValue >= NSWindow.Level.popUpMenu.rawValue { return event }
            self.dismissPopover()
            return event
        }
    }
    private func dismissPopover() {
        // A Picker's tracking loop can outlive its parent popover unless its
        // native menu is cancelled first.
        let menus = popoverMenus
        for menu in menus { menu.cancelTracking() }
        popover.performClose(nil)
    }
    private func stopPopoverMonitors() {
        popoverMenuObservers.forEach(NotificationCenter.default.removeObserver)
        popoverMenuObservers = []
        popoverMenus = []
        if let popoverGlobalMonitor { NSEvent.removeMonitor(popoverGlobalMonitor) }
        if let popoverLocalMonitor { NSEvent.removeMonitor(popoverLocalMonitor) }
        popoverGlobalMonitor = nil
        popoverLocalMonitor = nil
    }
    func popoverDidClose(_ notification: Notification) { stopPopoverMonitors() }

    // Opening the app/login item keeps menu-bar-only semantics. Explicit
    // Settings/Edit commands are the only way to present the workspace.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        stopPopoverMonitors()
        if let settingsKeyMonitor { NSEvent.removeMonitor(settingsKeyMonitor) }
        AppStore.shared.save(); WindowEngine.shared.stop()
    }

    private func configureMenus() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item)
            return submenu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", shift: Bool = false, responder: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : .command
            item.target = responder ? nil : self
            menu.addItem(item)
        }
        let app = menu("MACZONE")
        add(app, "About MACZONE", #selector(openAbout))
        app.addItem(.separator())
        add(app, "Settings…", #selector(openSettings), ",")
        app.addItem(.separator())
        add(app, "Hide MACZONE", #selector(NSApplication.hide(_:)), "h", responder: true)
        add(app, "Quit MACZONE", #selector(NSApplication.terminate(_:)), "q", responder: true)
        let edit = menu("Edit")
        add(edit, "Undo", #selector(undoLayout), "z")
        add(edit, "Redo", #selector(redoLayout), "z", shift: true)
        edit.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            add(edit, title, Selector(action), key, responder: true)
        }
        let layouts = menu("Layouts")
        add(layouts, "New Layout", #selector(newLayout), "n")
        add(layouts, "Apply to Display", #selector(applyLayout), "\r")
        add(layouts, "Preview Layout", #selector(previewLayout), "p", shift: true)
        layouts.addItem(.separator())
        add(layouts, "Import Layouts…", #selector(importLayouts), "i", shift: true)
        add(layouts, "Export Layouts…", #selector(exportLayouts), "e", shift: true)
        let windows = menu("Window")
        add(windows, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", responder: true)
        add(windows, "Zoom", #selector(NSWindow.performZoom(_:)), responder: true)
        add(windows, "Close", #selector(NSWindow.performClose(_:)), "w", responder: true)
        NSApp.windowsMenu = windows
        #if MACZONE_UI_QA
        let qa = menu("Visual QA")
        add(qa, "Editor at 980 × 660", #selector(compactPreview))
        add(qa, "Editor at 1240 × 800", #selector(defaultPreview))
        add(qa, "Show Popover", #selector(showPreviewPopover))
        #endif
        NSApp.mainMenu = main
    }
    @objc private func openSettings() { showSettings() }
    @objc private func openAbout() { showWorkspace("diagnostics") }
    @objc private func undoLayout() { AppStore.shared.undo() }
    @objc private func redoLayout() { AppStore.shared.redo() }
    @objc private func newLayout() { AppStore.shared.addLayout(); showWorkspace("layouts") }
    @objc private func applyLayout() { AppStore.shared.applyLayout() }
    @objc private func previewLayout() { WindowEngine.shared.preview(layout: AppStore.shared.selectedLayout) }
    @objc private func importLayouts() { AppStore.shared.importLayouts() }
    @objc private func exportLayouts() { AppStore.shared.exportLayouts() }
    #if MACZONE_UI_QA
    @objc private func compactPreview() { sizePreview(NSSize(width: 980, height: 660), settings: false) }
    @objc private func defaultPreview() { sizePreview(NSSize(width: 1240, height: 800), settings: false) }
    #endif
}

struct MenuBarView: View {
    @ObservedObject var store = AppStore.shared
    var open: (String) -> Void
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) { BrandMark().frame(width: 30, height: 30); Text("MACZONE").font(.system(size: 13, weight: .bold)).tracking(1); Spacer(); Button { open("layouts") } label: { IconLabel("Edit", "arrow-up-right").font(.system(size: 12)) }.buttonStyle(ReadableGlassButtonStyle()).help("Open layout editor") }
            if let display = store.selectedDisplay {
                Text(display.name).font(.system(size: 11)).foregroundStyle(.secondary)
                let layout = store.layout(for: display)
                GeometryReader { proxy in
                    ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                        Button { close(); WindowEngine.shared.snap(index, display: display) } label: {
                            RoundedRectangle(cornerRadius: 9).fill(Brand.navy).overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.ice.opacity(0.25))).overlay(Text("\(index+1)").font(.system(size: 18, weight: .medium, design: .rounded)).foregroundStyle(Brand.ice))
                        }.buttonStyle(.plain)
                            .frame(width: zone.width*proxy.size.width-4, height: zone.height*proxy.size.height-4)
                            .position(x: (zone.x+zone.width/2)*proxy.size.width, y: (zone.y+zone.height/2)*proxy.size.height)
                            .help("Move focused window to \(zone.name)").accessibilityLabel("Snap to zone \(index+1)")
                    }
                }.frame(height: 135)
                Picker("Layout", selection: Binding(get: { store.layout(for: display).id }, set: { store.assignLayout($0, to: display) })) { ForEach(store.library.layouts) { Text($0.name).tag($0.id) } }
            }
            HStack {
                action("Left Half", "half.left", "arrow-left")
                action("Fill Display", "fill", "maximize")
                action("Right Half", "half.right", "arrow-right")
                action("Restore", "restore", "rotate-ccw")
            }.frame(maxWidth: .infinity)
            Divider()
            Button { open("sessions") } label: { IconLabel("Saved Sessions", "history") }.buttonStyle(.plain)
            Button { MACZONEDelegate.current?.showSettings() } label: {
                HStack { IconLabel("Settings…", "settings"); Spacer(); Text("⌘,").foregroundStyle(.secondary) }
            }.buttonStyle(.plain).keyboardShortcut(",", modifiers: .command)
            HStack {
                Button { store.library.preferences.enabled.toggle() } label: { IconLabel(store.library.preferences.enabled ? "Pause" : "Resume", store.library.preferences.enabled ? "pause" : "play") }.buttonStyle(.plain)
                Spacer()
                Button("Quit MACZONE") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }.padding(22).frame(width: 336)
            .preferredColorScheme(store.library.preferences.appearance == "system" ? nil : store.library.preferences.appearance == "dark" ? .dark : .light)
    }
    private func action(_ label: String, _ command: String, _ icon: String) -> some View {
        Button { close(); WindowEngine.shared.perform(command) } label: { Lucide(name: icon).frame(maxWidth: .infinity) }.buttonStyle(ReadableGlassButtonStyle()).help(label).accessibilityLabel(label)
    }
}
