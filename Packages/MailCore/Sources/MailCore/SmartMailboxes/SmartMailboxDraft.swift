import Foundation

/// A smart mailbox as its editor holds it while it's changed: a name, a symbol, and either the VIPs, for the VIPs box,
/// or conditions joined by All or Any, as a rule's are (`ConditionDraft`). `smartMailbox` is what it saves, once
/// every value reads.
public struct SmartMailboxDraft: Identifiable, Equatable, Sendable {
    /// What the box holds, as the editor shows it.
    public enum Contents: Equatable, Sendable {
        /// The VIPs' addresses, as typed.
        case vips([String])
        case conditions(RuleDraft.Joiner, [ConditionDraft])
    }

    public let id: SmartMailbox.ID
    public var name: String
    public var symbol: String
    public var contents: Contents
    /// The name the box had, and the title it was shown under: a starting box keeps its own name, read in each
    /// device's language, until the reader types another.
    private let named: Named?

    private struct Named: Equatable, Sendable {
        let name: SmartMailbox.Name
        let title: String
    }

    /// A new box, holding the mail that meets one condition on the sender, not filled in yet.
    public init() {
        id = SmartMailbox.ID(rawValue: UUID().uuidString)
        name = ""
        symbol = "gearshape"
        contents = .conditions(.all, [ConditionDraft(.text(.sender, .contains, ""))])
        named = nil
    }

    /// The draft of `box`, shown as `title`, with `vips` the VIPs now; `nil` for a box whose condition is more than
    /// the editor shows, as `RuleDraft` has it.
    public init?(_ box: SmartMailbox, titled title: String, vips: VIPList) {
        switch box.filter {
        case .vips:
            contents = .vips(vips.addresses)
        case .condition(let condition):
            guard let rule = RuleDraft(MailRule(name: title, condition: condition, actions: [])) else { return nil }
            contents = .conditions(rule.joiner, rule.conditions)
        }
        id = box.id
        name = title
        symbol = box.symbol
        named = Named(name: box.name, title: title)
    }

    /// A new box holding what `query` finds, named after the words and people in it; `nil` for an empty query or one
    /// with a term only the service can answer, as `in:sent`.
    public init?(query: SearchQuery) {
        let kinds = query.terms.compactMap(ConditionDraft.Kind.init(searchTerm:))
        guard !kinds.isEmpty, kinds.count == query.terms.count else { return nil }
        self.init()
        name = kinds.compactMap(\.typedText).joined(separator: ", ")
        symbol = "magnifyingglass"
        contents = .conditions(.all, kinds.map(ConditionDraft.init))
    }

    /// The conditions, or none for the VIPs box.
    public var conditions: [ConditionDraft] {
        guard case .conditions(_, let conditions) = contents else { return [] }
        return conditions
    }

    /// The VIPs to keep, lowercased, each once, leaving out what isn't an address; `nil` outside the VIPs box.
    public var vips: VIPList? {
        guard case .vips(let typed) = contents else { return nil }
        return VIPList(typed)
    }

    /// The box the draft makes, or `nil` while the name is empty, a condition's value doesn't read or there is none.
    public var smartMailbox: SmartMailbox? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let filter: SmartMailbox.Filter
        switch contents {
        case .vips:
            filter = .vips
        case .conditions(let joiner, let conditions):
            let parts = conditions.compactMap(\.condition)
            guard !parts.isEmpty, parts.count == conditions.count else { return nil }
            filter = .condition(joiner == .all ? .all(parts) : .any(parts))
        }
        let kept = named.flatMap { $0.title == name ? $0.name : nil } ?? .custom(name)
        return SmartMailbox(id: id, name: kept, symbol: symbol, filter: filter)
    }
}

extension ConditionDraft.Kind {
    /// The condition a search term stands for, as the store's search reads it offline; `nil` for a term only the
    /// service answers.
    init?(searchTerm term: SearchQuery.Term) {
        switch (term.name, term.value.lowercased()) {
        case (nil, _): self = .text(.anyText, .contains, term.value)
        case ("is", "unread"): self = .flag(.unread, true)
        case ("is", "read"): self = .flag(.unread, false)
        case ("is", "starred"): self = .flag(.starred, true)
        case ("is", "important"): self = .flag(.important, true)
        case ("has", "attachment"): self = .flag(.hasAttachments, true)
        case ("from", _): self = .text(.sender, .contains, term.value)
        case ("to", _): self = .text(.recipients, .contains, term.value)
        case ("subject", _): self = .text(.subject, .contains, term.value)
        case ("label", _): self = .label(term.value)
        default: return nil
        }
    }

    /// What the reader typed for a text condition, which names a box saved from a search.
    fileprivate var typedText: String? {
        guard case .text(_, _, let value) = self else { return nil }
        return value
    }
}
