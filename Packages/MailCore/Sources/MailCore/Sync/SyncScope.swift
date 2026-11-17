/// How much of an account a sync keeps.
public enum SyncScope: Equatable, Sendable {
    /// The offline window (ADR-007): 90 days of Inbox, Sent, Starred and Drafts, 30 of everything else, and the
    /// address book.
    case window
    /// Only the newest `limit` Inbox conversations, for a small device such as the watch (ADR-023). No other mailbox
    /// and no address book.
    case inboxHead(limit: Int)
}
