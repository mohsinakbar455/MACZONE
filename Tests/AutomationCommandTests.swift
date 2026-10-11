import Foundation

@main struct AutomationCommandTests {
    static func main() {
        let cases: [(String, AutomationCommand?)] = [
            ("maczone://cycle", .cycleLayout), ("maczone://cycle/", .cycleLayout),
            ("maczone://settings", .settings),
            ("maczone://layout/1", .layoutSlot(0)), ("maczone://layout/6", .layoutSlot(5)),
            ("maczone://layout/0", nil), ("maczone://layout/7", nil),
            ("maczone://layout/01", nil), ("maczone://layout/1/extra", nil),
            ("maczone://cycle?command=quit", nil), ("maczone://cycle#x", nil),
            ("https://cycle", nil), ("maczone://quit", nil),
            ("maczone://user@cycle", nil), ("maczone://cycle:123", nil)
        ]
        for (input, expected) in cases {
            precondition(AutomationCommand(url: URL(string: input)!) == expected, input)
        }
        print("Passed \(cases.count) Alfred automation URL checks.")
    }
}
