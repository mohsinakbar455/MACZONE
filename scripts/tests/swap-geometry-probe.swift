// Read-only swap diagnostic: window IDs and geometry only. No AX writes,
// screenshots, document titles, permission requests, or event injection.
import AppKit

@main struct SwapGeometryProbe {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 4, let firstID = UInt32(args[1]), let secondID = UInt32(args[3]), firstID != secondID else {
            print("Usage: swap-geometry-probe <bundleID> <windowID> <bundleID> <windowID>"); exit(2)
        }
        let ids = [firstID, secondID]
        for (bundle, id) in [(args[0],firstID),(args[2],secondID)] {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
                  WindowServerSnapshot.visibleWindows().contains(where: { $0.id == id && $0.pid == app.processIdentifier }) else {
                print("BLOCKED: window \(id) is not visible or belongs to another app"); exit(2)
            }
        }
        func frames() -> [CGRect]? {
            let result = ids.compactMap { WindowServerSnapshot.frame(id:$0) }
            return result.count == 2 ? result : nil
        }
        func matches(_ a: [CGRect], _ b: [CGRect]) -> Bool {
            zip(a,b).allSatisfy { a,b in
                abs(a.minX-b.minX) <= 3 && abs(a.minY-b.minY) <= 3 && abs(a.width-b.width) <= 3 && abs(a.height-b.height) <= 3
            }
        }
        guard let original = frames() else { print("BLOCKED: missing frames"); exit(2) }
        let target = [original[1],original[0]]
        var previous = original
        let start = ProcessInfo.processInfo.systemUptime
        var lastChange = start
        var moved = false
        print("READY: click the yellow bead, choose Swap Windows, then leave both windows untouched. Capturing for at most 30 seconds.")
        print("original=\(original) target=\(target)"); fflush(stdout)
        while ProcessInfo.processInfo.systemUptime-start < 30 {
            let now = ProcessInfo.processInfo.systemUptime
            guard let current = frames() else { print("BLOCKED: window disappeared"); exit(2) }
            if current != previous {
                print("t=\(String(format: "%.3f",now-start)) frames=\(current)"); fflush(stdout)
                lastChange = now; previous = current
                if !matches(current,original) { moved = true }
            }
            if moved && now-lastChange >= 1 {
                if matches(current,target) { print("PASS: both windows remain in the exchanged slots"); return }
                if matches(current,original) { print("FAIL: windows moved, then returned to their original slots"); exit(1) }
                print("FAIL: exchange stopped at different geometry"); exit(1)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        print("BLOCKED: no completed exchange observed in capture interval"); exit(2)
    }
}
