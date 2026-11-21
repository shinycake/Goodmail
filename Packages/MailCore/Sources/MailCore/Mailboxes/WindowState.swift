public import Foundation

/// What one window shows: the list beside the mailboxes, the thread open from it, the Inbox's category, and whether
/// the window is the whole viewer or that one thread alone. The scene coordinator keeps it in step as the reader
/// moves, rebuilds either arrangement from it when the window changes width, and saves it so the system can restore
/// the window or hand it off to another device.
/// A state saved before windows had a filter reads as unfiltered.
public struct WindowState: Equatable, Codable, Sendable {
    /// The list beside the mailboxes, and the thread open from it.
    public enum List: Equatable, Codable, Sendable {
        /// The list is titled when it is built, from the labels and accounts then, so a renamed label or account
        /// shows its new name. State saved by builds that kept a `title` here still reads: the key is ignored.
        case mailbox(Mailbox, thread: ThreadSummary.ID?)
        case scheduled
        /// Snoozed threads, read as in All Mail since they are out of the Inbox.
        case snoozed(thread: ThreadSummary.ID?)
        /// A smart mailbox's conversations, read as in All Mail, as search's are: they come from any mailbox.
        case smart(SmartMailbox.ID, thread: ThreadSummary.ID?)
    }

    /// The `NSUserActivity` type a window's state travels as, declared in the app's `NSUserActivityTypes`.
    public static let activityType = "com.idanbirman.goodmail.window"
    /// The activity's `userInfo` key for `saved()`.
    public static let activityKey = "state"

    public var list: List
    /// The Inbox's category, so a rebuilt Inbox opens on it.
    public var category: InboxCategory
    /// What the list is filtered by. It stays when the window moves to another mailbox, as the category does.
    public var filter = ListFilter.none
    /// How far a narrow window's one stack goes. Not saved: a restored or handed-off window opens on its list.
    public var depth = Depth.list
    /// What the window lays out. A message window always has its thread open: the methods that close the thread, or
    /// read a state without one, make it a viewer.
    public private(set) var layout = Layout.viewer

    /// What a window lays out around what it shows.
    public enum Layout: String, Equatable, Codable, Sendable {
        /// The mailboxes, the list and the open thread, as many of them as the window's width holds.
        case viewer
        /// The open thread alone, as a conversation opened in a window of its own on the Mac. Its list is kept for
        /// moving the thread from it and for titles, and isn't shown.
        case message
    }

    /// How far a narrow window's one stack goes. A wide window shows the mailboxes and the list side by side.
    public enum Depth: Equatable, Sendable {
        /// The list, and the thread open from it.
        case list
        /// Back at the mailboxes, the list under them kept only for a wide window.
        case mailboxes
    }

    private enum CodingKeys: String, CodingKey {
        case list, category, filter, layout
    }

    public init(
        list: List = .mailbox(.inbox, thread: nil), category: InboxCategory = .primary,
        filter: ListFilter = .none, depth: Depth = .list
    ) {
        self.list = list
        self.category = category
        self.filter = filter
        self.depth = depth
    }

    /// Reads a saved state. One saved before windows had layouts is a viewer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            list: try container.decode(List.self, forKey: .list),
            category: try container.decode(InboxCategory.self, forKey: .category),
            filter: try container.decodeIfPresent(ListFilter.self, forKey: .filter) ?? .none)
        self = laidOut(as: try container.decodeIfPresent(Layout.self, forKey: .layout) ?? .viewer)
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
        case .mailbox(_, let thread?), .snoozed(let thread?), .smart(_, let thread?):
            readingMailbox.map { (thread, $0) }
        case .mailbox, .scheduled, .snoozed, .smart: nil
        }
    }

    /// Opens `thread` from the shown list, or `nil` closes it. Scheduled holds messages, not threads. A thread opens
    /// over the list, so a narrow window is no longer back at the mailboxes.
    /// Closing the thread makes a message window a viewer.
    public mutating func setThread(_ thread: ThreadSummary.ID?) {
        if thread == nil { layout = .viewer } else { depth = .list }
        switch list {
        case .mailbox(let mailbox, _): list = .mailbox(mailbox, thread: thread)
        case .snoozed: list = .snoozed(thread: thread)
        case .smart(let box, _): list = .smart(box, thread: thread)
        case .scheduled: break
        }
    }

    /// A new window that opens `thread`, read in `mailbox`. It keeps this window's list when that is where the thread
    /// was read; a thread found elsewhere, such as in search, opens over its own mailbox.
    /// `layout` says whether the new window is the whole viewer or the thread alone.
    public func opening(_ thread: ThreadSummary.ID, in mailbox: Mailbox, as layout: Layout = .viewer) -> WindowState {
        var opened = self
        if readingMailbox != mailbox { opened.list = .mailbox(mailbox, thread: nil) }
        opened.setThread(thread)
        return opened.laidOut(as: layout)
    }

    /// This state laid out as `layout`, or as a viewer when it asks for a message window with no thread open.
    public func laidOut(as layout: Layout) -> WindowState {
        var laidOut = self
        laidOut.layout = openThread == nil ? .viewer : layout
        return laidOut
    }

    /// The mailbox a thread opened from the shown list is read in. Scheduled holds messages, not threads.
    public var readingMailbox: Mailbox? {
        switch list {
        case .mailbox(let mailbox, _): mailbox
        case .snoozed, .smart: .allMail
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
        return kept.laidOut(as: kept.layout)
    }
}
