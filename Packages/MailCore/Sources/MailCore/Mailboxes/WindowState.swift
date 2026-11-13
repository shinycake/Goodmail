import Foundation

/// What one window shows: the list beside the mailboxes, the thread open from it, and the Inbox's category. The
/// scene coordinator keeps it in step as the reader moves, rebuilds either arrangement from it when the window
/// changes width, and saves it so the system can restore the window or hand it off to another device.
public struct WindowState: Equatable, Codable, Sendable {
    /// The list beside the mailboxes, and the thread open from it.
    public enum List: Equatable, Codable, Sendable {
        case mailbox(Mailbox, title: String?, thread: ThreadSummary.ID?)
        case scheduled
        /// Snoozed threads, read as in All Mail since they are out of the Inbox.
        case snoozed(thread: ThreadSummary.ID?)
    }

    /// The `NSUserActivity` type a window's state travels as, declared in the app's `NSUserActivityTypes`.
    public static let activityType = "com.idanbirman.goodmail.window"
    /// The activity's `userInfo` key for `saved()`.
    public static let activityKey = "state"

    public var list: List
    /// The Inbox's category, so a rebuilt Inbox opens on it.
    public var category: InboxCategory

    public init(list: List = .mailbox(.inbox, title: nil, thread: nil), category: InboxCategory = .primary) {
        self.list = list
        self.category = category
    }

    /// Reads a state `saved()` wrote. Throws for anything else, such as data from a later build.
    public init(saved data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    public func saved() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// The thread open from the shown list, and the mailbox it is read in.
    public var openThread: (id: ThreadSummary.ID, mailbox: Mailbox)? {
        switch list {
        case .mailbox(let mailbox, _, let thread?): (thread, mailbox)
        case .snoozed(let thread?): (thread, .allMail)
        case .mailbox, .scheduled, .snoozed: nil
        }
    }

    /// Opens `thread` from the shown list, or `nil` closes it. Scheduled holds messages, not threads.
    public mutating func setThread(_ thread: ThreadSummary.ID?) {
        switch list {
        case .mailbox(let mailbox, let title, _): list = .mailbox(mailbox, title: title, thread: thread)
        case .snoozed: list = .snoozed(thread: thread)
        case .scheduled: break
        }
    }

    /// This state without what belongs to accounts outside `accounts`, as when a window is restored after one was
    /// removed: an account's own mailbox gives way to the Inbox, and a thread of a gone account closes.
    public func keeping(_ accounts: [AccountID]) -> WindowState {
        var kept = self
        if case .mailbox(let mailbox, _, _) = list, let account = mailbox.accountID, !accounts.contains(account) {
            kept.list = WindowState().list
        } else if let thread = openThread?.id, !accounts.contains(thread.accountID) {
            kept.setThread(nil)
        }
        return kept
    }
}
