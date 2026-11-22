import MailCore

/// The people offered under a recipient field, and the one Return and Tab complete with: the first, until Up and
/// Down move the highlight.
nonisolated struct SuggestionList: Equatable, Sendable {
    let contacts: [Contact]
    private(set) var highlighted: Int

    /// The list for `contacts`, highlighting the first; `nil` when there is nobody to offer.
    init?(_ contacts: [Contact]) {
        guard !contacts.isEmpty else { return nil }
        self.contacts = contacts
        highlighted = 0
    }

    /// The person Return or Tab adds.
    var choice: Contact { contacts[highlighted] }

    enum Step: Equatable, Sendable {
        case up
        case down
    }

    /// Moves the highlight one person up or down, staying on the first or the last at the ends.
    mutating func move(_ step: Step) {
        switch step {
        case .up: highlighted = max(highlighted - 1, 0)
        case .down: highlighted = min(highlighted + 1, contacts.count - 1)
        }
    }
}
