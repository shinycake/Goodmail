import Foundation

/// A list of threads to read: one label, in every account or in one, or All Mail.
public struct Mailbox: Hashable, Codable, Sendable {
    /// `nil` for All Mail: every thread outside Spam and Trash.
    public var labelID: String?
    /// `nil` for a mailbox that blends every account. User labels belong to one account, since their IDs do.
    public var accountID: AccountID?

    public init(labelID: String?, accountID: AccountID? = nil) {
        self.labelID = labelID
        self.accountID = accountID
    }

    public static let inbox = Mailbox(labelID: SystemLabel.inbox)
    public static let starred = Mailbox(labelID: SystemLabel.starred)
    public static let sent = Mailbox(labelID: SystemLabel.sent)
    public static let drafts = Mailbox(labelID: SystemLabel.draft)
    public static let allMail = Mailbox(labelID: nil)
    public static let spam = Mailbox(labelID: SystemLabel.spam)
    public static let trash = Mailbox(labelID: SystemLabel.trash)

    /// The mailboxes every account has, in the order the mailbox list shows them.
    public static let standard: [Mailbox] = [.inbox, .starred, .sent, .drafts, .allMail, .spam, .trash]

    /// Whether `thread` belongs here, judged by its labels.
    public func contains(_ thread: ThreadSummary) -> Bool {
        if let accountID, thread.id.accountID != accountID { return false }
        guard let labelID else {
            return !thread.labelIDs.contains(SystemLabel.spam) && !thread.labelIDs.contains(SystemLabel.trash)
        }
        return thread.labelIDs.contains(labelID)
    }
}

/// The user's own labels, the unread counts and the scheduled messages the mailbox list shows.
public struct MailboxDirectory: Equatable, Sendable {
    public struct Label: Equatable, Sendable {
        public var mailbox: Mailbox
        public var name: String
        /// `#rrggbb`, when the user picked a color.
        public var color: String?

        public init(mailbox: Mailbox, name: String, color: String?) {
            self.mailbox = mailbox
            self.name = name
            self.color = color
        }
    }

    /// Visible user labels, by name.
    public var labels: [Label]
    /// Unread threads per mailbox; mailboxes with none are left out.
    public var unreadCounts: [Mailbox: Int]
    /// Messages waiting to go at a time the writer picked, in every account.
    public var scheduledCount: Int

    public init(labels: [Label] = [], unreadCounts: [Mailbox: Int] = [:], scheduledCount: Int = 0) {
        self.labels = labels
        self.unreadCounts = unreadCounts
        self.scheduledCount = scheduledCount
    }
}
