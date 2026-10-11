import Foundation

@main struct LayoutShortcutRuleTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }
    static func main() throws {
        var library = Library()
        let first = library.layouts[0], second = library.layouts[1]
        library.shortcuts["layout.\(second.id.uuidString)"] = "Control+Command+2"
        library.migrateLayoutShortcuts()
        expect(library.layoutShortcutSlots?.count == 6, "Six layout slots are initialized")
        expect(library.shortcutLayout(0)?.id == second.id, "An existing bound layout gets a slot")
        expect(library.shortcuts[Library.slotCommand(0)] == "Control+Command+2", "Existing shortcut is carried over")
        expect(library.shortcuts["layout.\(second.id.uuidString)"] == nil, "Migrated key is not registered twice")
        let slots = library.layoutShortcutSlots
        library.migrateLayoutShortcuts()
        expect(library.layoutShortcutSlots == slots, "Migration is idempotent")
        library.layouts.reverse()
        if let index = library.layouts.firstIndex(where: { $0.id == second.id }) { library.layouts[index].name = "Renamed" }
        expect(library.shortcutLayout(0)?.name == "Renamed", "Rename and reorder retain the bound layout")
        library.setShortcutLayout(first.id, slot: 0)
        expect(library.shortcuts[Library.slotCommand(0)] == "Control+Command+2", "Changing a slot keeps its recorded shortcut")
        expect(library.shortcutLayout(1) == nil, "Assigning an already-used layout moves it to the chosen slot")
        library.setShortcutLayout(second.id, slot: 5)
        expect(library.nextShortcutLayout(after: second.id)?.id == first.id, "Cycling wraps to the first slot")
        expect(library.nextShortcutLayout(after: UUID())?.id == first.id, "Unmapped active layout cycles to slot 01")
        expect(library.nextShortcutLayout(after: first.id)?.id == slots?["2"], "Cycling skips empty slots")
        library.layouts.removeAll { $0.id == slots?["2"] }
        expect(library.nextShortcutLayout(after: first.id)?.id == slots?["3"], "Cycling skips deleted layouts")
        expect(library.shortcutLayout(-1) == nil && library.shortcutLayout(6) == nil, "Only six slots are supported")
        let savedSlots = library.layoutShortcutSlots
        library.setShortcutLayout(UUID(), slot: 0)
        expect(library.layoutShortcutSlots == savedSlots, "Unknown layout cannot overwrite a slot")
        let restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        expect(restored.layoutShortcutSlots == library.layoutShortcutSlots && restored.shortcuts == library.shortcuts, "Slots and keys survive relaunch")
        for slot in 0..<6 { library.setShortcutLayout(nil, slot: slot) }
        expect(library.nextShortcutLayout(after: first.id) == nil, "Empty cycle does not invent a layout")
        library.migrateLayoutShortcuts()
        expect(library.layoutShortcutSlots?.isEmpty == true, "Explicitly cleared slots stay empty")
        library.setShortcutLayout(first.id, slot: 4)
        expect(library.nextShortcutLayout(after: first.id)?.id == first.id, "Single-slot cycle is stable")

        // Decode a real pre-change file shape, with all new optional keys absent.
        var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Library())) as! [String: Any]
        legacyObject.removeValue(forKey: "layoutShortcutSlots")
        let oldRule = AppRule(name: "Fixture", bundleID: "test.fixture", autoPlace: true, displayID: "display", zoneIndex: 1)
        legacyObject["appRules"] = [try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldRule))]
        var migrated = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        expect(migrated.layoutShortcutSlots == nil && migrated.appRules[0].layoutID == nil, "Old libraries and app rules decode")
        let pinned = migrated.layouts[1]
        migrated.preferences.perSpace = true
        migrated.spaceBindings["display:1"] = pinned.id
        migrated.pinRuleLayout(at: 0, displayID: "display", spaceID: "1")
        let rule = migrated.appRules[0]
        expect(rule.layoutID == pinned.id && rule.zoneID == pinned.zones[1].id, "Old rules pin the current Space's layout and previous zone")
        migrated.assignLayout(migrated.layouts[0].id, displayID: "display", spaceID: "1")
        expect(migrated.ruleZone(rule, displayID: "display", spaceID: "1")?.id == pinned.zones[1].id, "Rule placement is independent of the active layout")
        expect(migrated.layout(displayID: "display", spaceID: "1").id == migrated.layouts[0].id, "Rule resolution leaves the active layout unchanged")
        if let index = migrated.layouts.firstIndex(where: { $0.id == pinned.id }) { migrated.layouts[index].zones.reverse() }
        expect(migrated.ruleZone(rule, displayID: "display", spaceID: "2")?.id == pinned.zones[1].id, "Zone and Space reordering do not retarget rules")
        let restoredRules = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(migrated))
        expect(restoredRules.ruleZone(restoredRules.appRules[0], displayID: "display", spaceID: "2")?.id == pinned.zones[1].id, "Explicit rule target survives relaunch")
        var changed = rule
        changed.selectLayout(migrated.layouts[0])
        expect(changed.zoneIndex == 0 && changed.zoneID == migrated.layouts[0].zones[0].id, "Changing a rule layout resets its zone")
        if let index = migrated.layouts.firstIndex(where: { $0.id == pinned.id }) { migrated.layouts[index].zones.removeAll { $0.id == rule.zoneID } }
        expect(migrated.ruleZone(rule, displayID: "display", spaceID: "1") == nil, "Deleted zone does not silently fall back by index")
        migrated.layouts.removeAll { $0.id == pinned.id }
        expect(migrated.ruleZone(rule, displayID: "display", spaceID: "1") == nil, "Deleted layout does not use the active layout")
        var many = Library()
        many.layouts.append(.columns(5))
        for item in many.layouts { many.shortcuts["layout.\(item.id.uuidString)"] = "Control+Command+X" }
        many.migrateLayoutShortcuts()
        expect(many.shortcuts["layout.\(many.layouts[6].id.uuidString)"] != nil, "Additional existing layout shortcuts are preserved")
        print("Passed \(checks) layout shortcut, rule targeting, and migration checks.")
    }
}
