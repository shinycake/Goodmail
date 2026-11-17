public import Foundation

/// What one window shows: the list beside the mailboxes, the thread open from it, and the Inbox's category. The
/// scene coordinator keeps it in step as the reader moves, rebuilds either arrangement from it when the window
/// changes width, and saves it so the system can restore the window or hand it off to another device.
public struct WindowState: Equatable, Codable, Sendable {
    /// The list beside the mailboxes, and the thread open from it.
    public enum List: Equatable, Codable, Sendable {
        /// The list is titled when it is built, from the labels and accounts then, so a renamed label or account
        /// shows its new name. State saved by builds that kept a `title` here still reads: the key is ignored.
        case mailbox(Mailbox, thread: ThreadSummary.ID?)
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
    /// How far a narrow window's one stack goes. Not saved: a restored or handed-off window opens on its list.
    public var depth = Depth.list

    /// How far a narrow window's one stack goes. A wide window shows the mailboxes and the list side by side.
    public enum Depth: Equatable, Sendable {
        /// The list, and the thread open from it.
        case list
        /// Back at the mailboxes, the list under them kept only for a wide window.
        case mailboxes
    }

    private enum CodingKeys: String, CodingKey {
        case list, category
    }

    public init(
        list: List = .mailbox(.inbox, thread: nil), category: InboxCategory = .primary, depth: Depth = .list
    ) {
        self.list = list
        self.category = category
        self.depth = depth
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
        case .mailbox(_, let thread?), .snoozed(let thread?): readingMailbox.map { (thread, $0) }
        case .mailbox, .scheduled, .snoozed: nil
        }
    }

    /// Opens `thread` from the shown list, or `nil` closes it. Scheduled holds messages, not threads. A thread opens
    /// over the list, so a narrow window is no longer back at the mailboxes.
    public mutating func setThread(_ thread: ThreadSummary.ID?) {
        if thread != nil { depth = .list }
        switch list {
        case .mailbox(let mailbox, _): list = .mailbox(mailbox, thread: thread)
        case .snoozed: list = .snoozed(thread: thread)
        case .scheduled: break
        }
    }

    /// A new window that opens `thread`, read in `mailbox`. It keeps this window's list when that is where the thread
    /// was read; a thread found elsewhere, such as in search, opens over its own mailbox.
    public func opening(_ thread: ThreadSummary.ID, in mailbox: Mailbox) -> WindowState {
        var opened = self
        if readingMailbox != mailbox { opened.list = .mailbox(mailbox, thread: nil) }
        opened.setThread(thread)
        return opened
    }

    /// The mailbox a thread opened from the shown list is read in. Scheduled holds messages, not threads.
    private var readingMailbox: Mailbox? {
        switch list {
        case .mailbox(let mailbox, _): mailbox
        case .snoozed: .allMail
        case .scheduled: nil
        }
    }

    /// This state without what belongs to accounts outside `accounts`, as when a window is restored after one was
    /// removed: an account's own mailbox gives way to the Inbox, and a thread of a gone account closes.
    public func keeping(_ accounts: [AccountID]) -> WindowState {
        var kept = self
        if case .mailbox(let mailbox, _) = list, let account = mailbox.accountID, !accounts.contains(account) {
            kept.list = WindowState().list
        } else if let thread = openThread?.id, !accounts.contains(thread.accountID) {
            kept.setThread(nil)
        }
        return kept
    }
}
