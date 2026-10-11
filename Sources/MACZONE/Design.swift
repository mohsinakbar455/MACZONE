// MACZONE visual system, 2026-10-08. GPL-3.0.
import SwiftUI
import AppKit

// Use the established property wrapper explicitly. The CLT SDK exposes the new
// State macro but does not ship Xcode's SwiftUIMacros plugin.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Brand {
    static let black = Color(red: 23/255, green: 23/255, blue: 23/255)
    static let yellow = Color(red: 1, green: 225/255, blue: 79/255)
    static let navy = Color(red: 25/255, green: 40/255, blue: 83/255)
    static let ice = Color(red: 236/255, green: 244/255, blue: 247/255)
}

/// A quiet content surface. Navigation and floating controls keep native glass.
struct WorkspaceSurface: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            (scheme == .dark ? Brand.black : Brand.ice)
        } else {
            LinearGradient(colors: scheme == .dark
                ? [Brand.navy.opacity(0.38), Brand.black, Brand.black]
                : [Brand.ice, Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(scheme == .dark ? Brand.black : Brand.ice)
        }
    }
}

struct Lucide: View {
    let name: String
    var size: CGFloat = 17
    private static var cache: [String: NSImage] = [:]
    private var image: NSImage {
        if let cached = Self.cache[name] { return cached }
        let url = Bundle.main.resourceURL?.appendingPathComponent("Lucide/\(name).png")
        let result = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 24, height: 24))
        result.size = NSSize(width: 17, height: 17)
        result.isTemplate = true; Self.cache[name] = result; return result
    }
    var body: some View { Image(nsImage: image).resizable().renderingMode(.template).interpolation(.high).frame(width: size, height: size).accessibilityHidden(true) }
}

struct IconLabel: View {
    var title: String; var icon: String
    init(_ title: String, _ icon: String) { self.title = title; self.icon = icon }
    var body: some View { HStack(spacing: 7) { Lucide(name: icon); Text(title) } }
}

struct BrandMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w*0.23).fill(Brand.yellow)
                RoundedRectangle(cornerRadius: w*0.045).fill(Brand.black).frame(width: w*0.27, height: h*0.60).offset(x: w*0.18, y: h*0.20)
                RoundedRectangle(cornerRadius: w*0.045).fill(Brand.black).frame(width: w*0.29, height: h*0.265).offset(x: w*0.53, y: h*0.20)
                RoundedRectangle(cornerRadius: w*0.045).fill(Brand.navy).frame(width: w*0.29, height: h*0.265).offset(x: w*0.53, y: h*0.535)
            }
        }.accessibilityLabel("MACZONE")
    }
}

struct PrimaryButton: View {
    let title: String; let icon: String; let action: () -> Void
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            IconLabel(title, icon).fontWeight(.semibold).padding(.horizontal, 4)
                // Inactive prominent glass loses its tint. Black text must not
                // remain on the system's dark, inactive button surface.
                .foregroundStyle(appearsActive && isEnabled ? Brand.black : Color.primary)
        }
        .buttonStyle(.glassProminent).tint(Brand.yellow).controlSize(.large)
    }
}

/// Continuous native slider: macOS adds tick dots when `step:` is supplied.
/// Round at the binding boundary and retain explicit accessibility increments.
struct SmoothSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var increment: Double = 1
    var unit = "points"
    private func rounded(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, (value / increment).rounded() * increment))
    }
    var body: some View {
        Slider(value: Binding(get: { value }, set: { value = rounded($0) }), in: range)
            .accessibilityLabel(title)
            .accessibilityValue(unit == "percent" ? "\(Int((value * 100).rounded())) percent" : "\(Int(value.rounded())) \(unit)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = rounded(value + increment)
                case .decrement: value = rounded(value - increment)
                @unknown default: break
                }
            }
    }
}

struct ToolButton: View {
    let title: String; let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) { Lucide(name: icon) }.buttonStyle(ReadableGlassButtonStyle()).help(title).accessibilityLabel(title)
    }
}

/// Secondary actions use neutral native glass, not the workspace's yellow tint.
/// An explicit semantic label stays legible when an enabled window is inactive;
/// real disabled controls continue to use the system's disabled treatment.
struct ReadableGlassButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            if isEnabled { configuration.label.foregroundStyle(Color.primary) }
            else { configuration.label }
        }.buttonStyle(.glass).tint(nil)
    }
}

struct PageHeading: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 28, weight: .semibold))
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LayoutThumbnail: View {
    let layout: ZoneLayout
    var selected = false
    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                RoundedRectangle(cornerRadius: 3)
                    .fill(selected && index == 0 ? Brand.yellow : Brand.navy.opacity(selected ? 0.92 : 0.65))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Brand.ice.opacity(0.17)))
                    .frame(width: max(2, zone.width * proxy.size.width - 3), height: max(2, zone.height * proxy.size.height - 3))
                    .position(x: (zone.x+zone.width/2)*proxy.size.width, y: (zone.y+zone.height/2)*proxy.size.height)
            }
        }.padding(10).background(Brand.black, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EmptyState: View {
    let icon: String; let title: String; let detail: String; let button: String; let action: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Lucide(name: icon, size: 32).foregroundStyle(.secondary).padding(.bottom, 8)
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
            PrimaryButton(title: button, icon: "plus", action: action)
        }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func presentNameSheet(title: String, defaultValue: String, completion: @escaping (String) -> Void) {
    let alert = NSAlert(); alert.messageText = title
    alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
    let field = NSTextField(string: defaultValue); field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
    alert.accessoryView = field; alert.window.initialFirstResponder = field
    if alert.runModal() == .alertFirstButtonReturn {
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { completion(name) }
    }
}

func confirmDelete(_ title: String, action: () -> Void) {
    let alert = NSAlert(); alert.messageText = title; alert.informativeText = "This removes the saved item from MACZONE."
    alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel"); alert.alertStyle = .warning
    if alert.runModal() == .alertFirstButtonReturn { action() }
}
