import Foundation
import MailCore

/// The people what is typed in search names, which its filters offer: looked up off the main actor, one text at a
/// time. Newer text cancels the lookup for older text, so people found for text the field no longer holds are never
/// offered.
final class SearchPeople {
    /// The people found for one typed text.
    private struct Found {
        let text: String
        let contacts: [Contact]
    }

    private let lookUp: @Sendable (String) async -> [Contact]
    /// What the newest lookup to finish found, which is offered while the field holds its text.
    private var found = Found(text: "", contacts: [])
    /// The lookup for the newest text, while it runs.
    private var lookingUp: Task<Void, Never>?

    /// `lookUp` finds the people some text names; it reads the database, so it runs off the main actor.
    init(lookUp: @escaping @Sendable (String) async -> [Contact]) {
        self.lookUp = lookUp
    }

    isolated deinit {
        lookingUp?.cancel()
    }

    /// The people known now for `typed`: none until its lookup finishes.
    func people(for typed: String) -> [Contact] {
        found.text == Self.text(typed) ? found.contacts : []
    }

    /// Looks up the people `typed` names, unless they are known already or it is blank, and calls `didFind` once they
    /// are. Cancels the lookup for any earlier text. Returns the lookup it started, for a test to wait on.
    @discardableResult
    func lookUp(_ typed: String, then didFind: @escaping () -> Void) -> Task<Void, Never>? {
        lookingUp?.cancel()
        lookingUp = nil
        let text = Self.text(typed)
        guard !text.isEmpty, text != found.text else { return nil }
        let task = Task { [weak self, lookUp] in
            let contacts = await lookUp(text)
            guard !Task.isCancelled, let self else { return }
            found = Found(text: text, contacts: contacts)
            lookingUp = nil
            didFind()
        }
        lookingUp = task
        return task
    }

    private static func text(_ typed: String) -> String {
        typed.trimmingCharacters(in: .whitespaces)
    }
}
