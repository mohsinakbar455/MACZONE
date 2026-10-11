// MACZONE, 2026-10-11. GPL-3.0.
import Foundation

enum AutomationCommand: Equatable {
    case cycleLayout
    case layoutSlot(Int)
    case settings

    init?(url: URL) {
        guard url.scheme?.lowercased() == "maczone", url.user == nil,
              url.password == nil, url.port == nil, url.query == nil,
              url.fragment == nil else { return nil }
        switch (url.host?.lowercased(), url.path) {
        case ("cycle", ""), ("cycle", "/"): self = .cycleLayout
        case ("settings", ""), ("settings", "/"): self = .settings
        case ("layout", let path):
            guard path.count == 2, let slot = Int(path.dropFirst()), (1...6).contains(slot) else { return nil }
            self = .layoutSlot(slot - 1)
        default: return nil
        }
    }
}
