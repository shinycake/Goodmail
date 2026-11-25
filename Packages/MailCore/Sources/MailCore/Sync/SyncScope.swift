/// How much of an account a sync keeps.
public enum SyncScope: Equatable, Sendable {
    /// The offline window (ADR-007) the device keeps: its long window of Inbox, Sent, Starred and Drafts, its short
    /// one of everything else, and the address book.
    case window(OfflineWindow)
    /// Only the newest `limit` Inbox conversations, for a small device such as the watch (ADR-023). No other mailbox
    /// and no address book.
    case inboxHead(limit: Int)

    /// The windows whose headers the scope keeps. The head of the Inbox looks back as far as a handheld's window.
    var offlineWindow: OfflineWindow {
        switch self {
        case .window(let window): window
        case .inboxHead: .handheld
        }
    }

    /// How many threads a resync stores before it stops: all it lists, or the head's limit.
    var resyncLimit: Int {
        switch self {
        case .window: .max
        case .inboxHead(let limit): limit
        }
    }
}
