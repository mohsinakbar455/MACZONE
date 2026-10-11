import Foundation

@main struct WindowUpdateTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; if !value() { fatalError(message) }
    }
    static func main() {
        var requests = LatestFrameRequests()
        let old = requests.begin(1), current = requests.begin(1), other = requests.begin(2)
        expect(!requests.finish(1, token: old), "Old delayed work cannot pull a window back during resize")
        expect(requests.finish(1, token: current), "Only the latest requested frame may retry")
        expect(!requests.finish(1, token: current), "Completed retries cannot repeat")
        expect(requests.finish(2, token: other), "Other windows retain independent updates")
        let manual = requests.begin(1); requests.cancel(1)
        expect(!requests.finish(1, token: manual), "Starting a native move/resize cancels pending correction")
        let paused = requests.begin(2); requests.cancelAll()
        expect(!requests.finish(2, token: paused), "Pausing cancels pending corrections")
        var cache = OverlayInvalidation()
        let layout = ZoneLayout.columns(2), frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let prefs = Preferences()
        let first = OverlayPresentation(displayID: "display", frame: frame, layout: layout, selected: [layout.zones[0].id], preferences: prefs)
        let start = Date()
        var updates = 0
        for _ in 0..<1000 { if cache.needsUpdate(first) { updates += 1 } }
        expect(updates == 1, "1000 moves within the same zone rebuild the overlay only once")
        let second = OverlayPresentation(displayID: "display", frame: frame, layout: layout, selected: [layout.zones[1].id], preferences: prefs)
        expect(cache.needsUpdate(second), "Changing the highlighted zone redraws the overlay")
        var edited = layout; edited.zones[0].width = 0.4
        expect(cache.needsUpdate(OverlayPresentation(displayID: "display", frame: frame, layout: edited, selected: [], preferences: prefs)), "Edited geometry invalidates the overlay")
        var changed = prefs; changed.gap += 1
        expect(cache.needsUpdate(OverlayPresentation(displayID: "display", frame: frame, layout: edited, selected: [], preferences: changed)), "Changing overlay preferences redraws")
        cache.hide(); expect(cache.needsUpdate(first), "Hidden overlays can be shown again")
        print("Passed \(checks) window update checks; \(updates)/1000 unchanged overlay requests render (\(String(format: "%.2f", Date().timeIntervalSince(start)*1000)) ms decision loop).")
    }
}
