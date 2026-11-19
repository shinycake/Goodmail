public import Foundation

/// What touching and holding the app icon on the Home Screen offers. Each travels in its shortcut item as `encoded()`,
/// so the app reads back exactly what it offered.
public enum QuickAction: Hashable, Codable, Sendable {
    /// A new message from the first account.
    case newMessage
    /// The search field, ready to type in.
    case search
    /// Search with only its Unread filter: the unread mail in every account.
    case unread
    /// The newest draft, in the composer where it was left off.
    case draft(ThreadSummary.ID)
    /// One account's Inbox.
    case inbox(AccountID)

    /// The most the Home Screen shows. It drops the rest.
    public static let limit = 4

    /// The menu for `accounts`, in their order, and the newest draft, most useful first, as the Home Screen puts the
    /// first nearest the icon. Writing and finding mail lead, then the draft waiting to be finished, then each
    /// account's Inbox where there are several to choose between. With no account there is nothing to offer.
    public static func menu(accounts: [AccountID], newestDraft: ThreadSummary.ID?) -> [QuickAction] {
        guard !accounts.isEmpty else { return [] }
        let inboxes = accounts.count > 1 ? accounts.map(QuickAction.inbox) : []
        let draft = newestDraft.map(QuickAction.draft).map { [$0] } ?? []
        return Array(([.newMessage, .search, .unread] + draft + inboxes).prefix(limit))
    }

    /// The shortcut item's type: one per kind, as Apple asks, so the system can tell them apart.
    public var type: String {
        let kind =
            switch self {
            case .newMessage: "new-message"
            case .search: "search"
            case .unread: "unread"
            case .draft: "draft"
            case .inbox: "inbox"
            }
        return "com.idanbirman.goodmail.quick-action.\(kind)"
    }

    /// The action as its shortcut item carries it.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Reads an action `encoded()` wrote. Throws for anything else, such as one from a later build.
    public init(encoded data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}
