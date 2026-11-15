import Foundation
import MailCore

/// The rules that load remote images without asking, kept on this device: one per address or domain, listed domains
/// first and then senders, each alphabetically, as Settings shows them.
public struct ImageTrustRules {
    private let key: String
    /// Where "Always Load from This Sender" kept its addresses before domain rules. Read once and folded in.
    private let legacyKey: String
    private let defaults: UserDefaults

    public init(
        defaults: UserDefaults = .standard, key: String = "imageTrustRules", legacyKey: String = "trustedImageSenders"
    ) {
        self.defaults = defaults
        self.key = key
        self.legacyKey = legacyKey
    }

    public var all: [ImageTrustRule] {
        if let data = defaults.data(forKey: key),
            let rules = try? JSONDecoder().decode([ImageTrustRule].self, from: data)
        {
            return rules
        }
        return Self.sorted((defaults.stringArray(forKey: legacyKey) ?? []).compactMap(ImageTrustRule.init(sender:)))
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
