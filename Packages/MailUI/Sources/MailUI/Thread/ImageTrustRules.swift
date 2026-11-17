public import Foundation
public import MailCore

/// The rules that load remote images without asking: one per address or domain, listed domains first and then
/// senders, each alphabetically, as Settings shows them. They follow the reader to their other devices
/// (`Preferences.syncedSettings`), rule by rule.
public struct ImageTrustRules {
    private let key: String
    /// Where "Always Load from This Sender" kept its addresses before domain rules. Read once and folded in.
    private let legacyKey: String
    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard, key: String = standardKey, legacyKey: String = "trustedImageSenders"
    ) {
        self.defaults = defaults
        self.key = key
        self.legacyKey = legacyKey
    }

    /// Where the rules are kept, unless a test names another key.
    nonisolated public static let standardKey = "imageTrustRules"

    public var all: [ImageTrustRule] {
        if let data = defaults.data(forKey: key),
            let rules = try? JSONDecoder().decode([ImageTrustRule].self, from: data)
        {
            // Sorted on reading too, since rules taken up from another device are added at the end.
            return Self.sorted(rules)
        }
        return Self.sorted((defaults.stringArray(forKey: legacyKey) ?? []).compactMap(ImageTrustRule.init(sender:)))
    }

    /// Stores rules still kept where "Always Load from This Sender" kept them under the current key, so they sync.
    public func foldInLegacyRules() {
        guard defaults.data(forKey: key) == nil, defaults.object(forKey: legacyKey) != nil else { return }
        store(all)
    }

    /// Adds `rule`, in place of any rule for the same address or domain.
    public func add(_ rule: ImageTrustRule) {
        store(all.filter { !Self.sameTarget($0, rule) } + [rule])
    }

    public func remove(_ rule: ImageTrustRule) {
        store(all.filter { $0 != rule })
    }

    /// Puts `new` where `old` was, as an edit in Settings does, replacing any other rule for `new`'s target too.
    public func replace(_ old: ImageTrustRule, with new: ImageTrustRule) {
        store(all.filter { $0 != old && !Self.sameTarget($0, new) } + [new])
    }

    private func store(_ rules: [ImageTrustRule]) {
        // Encoding an array of plain enums can't fail.
        defaults.set(try? JSONEncoder().encode(Self.sorted(rules)), forKey: key)
        defaults.removeObject(forKey: legacyKey)
    }

    private static func sameTarget(_ a: ImageTrustRule, _ b: ImageTrustRule) -> Bool {
        a.kind == b.kind && a.value == b.value
    }

    private static func sorted(_ rules: [ImageTrustRule]) -> [ImageTrustRule] {
        rules.sorted { ($0.kind == .domain ? 0 : 1, $0.value) < ($1.kind == .domain ? 0 : 1, $1.value) }
    }
}
