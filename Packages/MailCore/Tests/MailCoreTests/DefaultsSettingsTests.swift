import Foundation
import Testing

@testable import MailCore

/// Uses the standard defaults, which every `UserDefaults.standard` reference sees at once, with keys of its own per
/// test: two instances of a named suite needn't agree right away on Linux. Serialized because Linux's `UserDefaults`
/// loses writes made from several threads at once; Apple's is thread-safe.
@Suite(.serialized)
struct DefaultsSettingsTests {
    private let defaults = UserDefaults.standard
    private let prefix = "DefaultsSettingsTests.\(UUID().uuidString)."

    private func key(_ name: String) -> String { prefix + name }

    @Test func valuesRoundTripThroughTheirSharedForm() throws {
        let keys = ["undo", "avatars", "swipe", "tints", "unset"].map(key)
        defaults.set(20, forKey: key("undo"))
        defaults.set(false, forKey: key("avatars"))
        defaults.set(["archive", "trash"], forKey: key("swipe"))
        defaults.set(["archive": "red", "flag": "orange"], forKey: key("tints"))
        let family = DefaultsValues(name: "prefs", keys: keys)
        let local = try family.local()
        #expect(local.values[key("unset")] == nil)
        #expect(local.scope == .only(Set(keys)))

        for name in keys { defaults.removeObject(forKey: name) }
        try family.apply(local.values.mapValues(SettingChange.set))
        #expect(defaults.object(forKey: key("undo")) as? Int == 20)
        #expect(defaults.object(forKey: key("avatars")) as? Bool == false)
        #expect(defaults.stringArray(forKey: key("swipe")) == ["archive", "trash"])
        #expect(defaults.dictionary(forKey: key("tints")) as? [String: String] == ["archive": "red", "flag": "orange"])
        #expect(try family.local() == local)
    }

    @Test func aRemovedValueLeavesTheDefaults() throws {
        defaults.set("orange", forKey: key("theme"))
        try DefaultsValues(name: "prefs", keys: [key("theme")]).apply([key("theme"): .removed])
        #expect(defaults.object(forKey: key("theme")) == nil)
    }

    @Test func aStringListMergesItemByItem() throws {
        defaults.set(["a", "b", "c"], forKey: key("lists"))
        let family = DefaultsList(name: "lists", key: key("lists"), storage: .strings)
        #expect(try family.local().values.keys.sorted() == ["a", "b", "c"])
        try family.apply(["b": .removed, "d": .set(Data("d".utf8))])
        #expect(defaults.stringArray(forKey: key("lists")) == ["a", "c", "d"])
    }

    @Test func aJSONListKeepsEachItemAsItWas() throws {
        let rules: [ImageTrustRule] = [.sender("a@example.com"), .domain("example.org", subdomains: .included)]
        defaults.set(try JSONEncoder().encode(rules), forKey: key("rules"))
        let local = try DefaultsList(name: "images", key: key("rules"), storage: .json).local()
        try DefaultsList(name: "images", key: key("copy"), storage: .json).apply(
            local.values.mapValues(SettingChange.set))
        let copied = try #require(defaults.data(forKey: key("copy")))
        #expect(Set(try JSONDecoder().decode([ImageTrustRule].self, from: copied)) == Set(rules))
    }
}
