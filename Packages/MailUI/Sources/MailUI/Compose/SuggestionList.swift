import MailCore

/// The people offered under a recipient field, and the one picked from the keyboard. Nobody is picked until Up or
/// Down moves to someone, so Return keeps what was typed unless the writer chose a person.
nonisolated struct SuggestionList: Equatable, Sendable {
    let contacts: [Contact]
    private(set) var highlight = Highlight.none

    enum Highlight: Equatable, Sendable {
        /// Nobody yet: Return adds what was typed, Tab the first person.
        case none
        case on(Int)
    }

    /// The list for `contacts`, with nobody picked; `nil` when there is nobody to offer.
    init?(_ contacts: [Contact]) {
        guard !contacts.isEmpty else { return nil }
        self.contacts = contacts
    }

    /// The person Up and Down moved to, which Return adds; `nil` while nobody is picked.
    var picked: Contact? {
        guard case .on(let index) = highlight else { return nil }
        return contacts[index]
    }

    /// The person Tab adds: the one picked, or else the first.
    var tabChoice: Contact { picked ?? contacts[0] }

    enum Step: Equatable, Sendable {
        case up
        case down
    }

    /// Moves the highlight one person up or down, onto the first from nobody, staying on the first or the last at
    /// the ends.
    mutating func move(_ step: Step) {
        switch (highlight, step) {
        case (.none, _): highlight = .on(0)
        case (.on(let index), .up): highlight = .on(max(index - 1, 0))
        case (.on(let index), .down): highlight = .on(min(index + 1, contacts.count - 1))
        }
    }
}
