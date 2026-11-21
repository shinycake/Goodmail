/// What a reader has to show of a conversation: nothing yet while its messages are fetched, its messages, or why it has
/// none to show. The messages come from the store as it changes, and the fetch says how asking the service went; the
/// two can come in either order, and each moves this one way (`received(_:)`, `fetched(_:)`).
public enum ConversationContent: Equatable, Sendable {
    /// None of its messages are on the device yet, and they are being fetched.
    case loading
    /// Its messages, oldest first.
    case shown([Message])
    /// It has nothing to show, and why.
    case unavailable(Unavailable)

    /// Why a conversation has nothing to show.
    public enum Unavailable: Equatable, Sendable {
        /// It was deleted: the service no longer has it, or it left the device while it was read.
        case gone
        /// Its messages aren't on the device and the service couldn't be asked, as offline. Fetching again may work.
        case unreachable
    }

    /// How a fetch of the conversation went.
    public enum Fetch: Equatable, Sendable {
        /// The service answered, and what it had is stored, which comes as `received(_:)`. `stored` says whether the
        /// store holds any of its messages now: none means it has nothing to show.
        case done(stored: Bool)
        /// The service says it has no such conversation.
        case notFound
        /// The service couldn't be asked.
        case failed
    }

    /// Its messages, while there are any to show.
    public var messages: [Message] {
        guard case .shown(let messages) = self else { return [] }
        return messages
    }

    /// The store's messages for it are now `messages`. None while some were shown means it left the device, as one
    /// deleted elsewhere does; none before the fetch is done is only the store not having them yet.
    public mutating func received(_ messages: [Message]) {
        if !messages.isEmpty {
            self = .shown(messages)
            return
        }
        switch self {
        case .shown: self = .unavailable(.gone)
        case .loading, .unavailable: break
        }
    }

    /// A fetch of it went as `fetch` says. What it found arrives through the store. Messages already shown stay
    /// whatever the fetch says: a service that can't find them now, as IMAP before its next sync, hasn't deleted them,
    /// and one that did takes them out of the store, which says so (`received(_:)`).
    public mutating func fetched(_ fetch: Fetch) {
        switch (fetch, self) {
        case (.done(stored: false), .loading): self = .unavailable(.gone)
        case (.done, _): break
        case (.notFound, .loading), (.notFound, .unavailable): self = .unavailable(.gone)
        case (.notFound, .shown): break
        case (.failed, .loading), (.failed, .unavailable(.unreachable)): self = .unavailable(.unreachable)
        case (.failed, .shown), (.failed, .unavailable(.gone)): break
        }
    }

    /// A fetch begins again, as from Try Again: a conversation out of reach waits for it.
    public mutating func refetching() {
        if self == .unavailable(.unreachable) { self = .loading }
    }
}
