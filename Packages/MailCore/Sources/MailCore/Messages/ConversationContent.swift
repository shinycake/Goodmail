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
        /// The service answered; what it had is stored, and comes as `received(_:)`.
        case done
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

    /// A fetch of it went as `fetch` says. What it found arrives through the store; a failure leaves messages already
    /// shown as they are.
    public mutating func fetched(_ fetch: Fetch) {
        switch (fetch, self) {
        case (.done, _): break
        case (.notFound, _): self = .unavailable(.gone)
        case (.failed, .loading), (.failed, .unavailable(.unreachable)): self = .unavailable(.unreachable)
        case (.failed, .shown), (.failed, .unavailable(.gone)): break
        }
    }

    /// A fetch begins again, as from Try Again: a conversation out of reach waits for it.
    public mutating func refetching() {
        if self == .unavailable(.unreachable) { self = .loading }
    }
}
