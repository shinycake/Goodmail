/// What one window shows: the list beside the mailboxes, the conversation it reads and where, the Inbox's category,
/// and whether the window is the whole viewer or that one conversation alone. The scene coordinator keeps it in step
/// as the reader moves, rebuilds either arrangement from it when the window changes width (`stack`, `columns`), and
/// saves it so the system can restore the window or hand it off to another device (`WindowState+Coding`).
///
/// A message window always reads a conversation, and a narrow window back at the mailboxes reads none: the methods
/// that change what is read keep both true.
public struct WindowState: Equatable, Sendable {
    /// The list beside the mailboxes. It says nothing of what is read, which is `reading`'s.
    public enum List: Hashable, Sendable {
        /// The list is titled when it is built, from the labels and accounts then, so a renamed label or account
        /// shows its new name.
        case mailbox(Mailbox)
        /// Messages waiting to be sent later, which are messages, not conversations: none opens from it, though one
        /// opened from an alert reads over it.
        case scheduled
        /// Snoozed conversations, read as in All Mail since they are out of the Inbox.
        case snoozed
        /// A smart mailbox's conversations, read as in All Mail, as search's are: they come from any mailbox.
        case smart(SmartMailbox.ID)

        /// Where a conversation opened from this list's own rows is read; `nil` for Scheduled, which has none.
        var readingMailbox: Mailbox? {
            switch self {
            case .mailbox(let mailbox): mailbox
            case .snoozed, .smart: .allMail
            case .scheduled: nil
            }
        }
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
    public private(set) var depth = Depth.list
    /// The conversation the window reads, and where; `nil` with none open.
    public private(set) var reading: Reading?
    /// What the window lays out.
    public private(set) var layout = Layout.viewer

    /// What a window lays out around what it shows.
    public enum Layout: String, Equatable, Codable, Sendable {
        /// The mailboxes, the list and the open conversation, as many of them as the window's width holds.
        case viewer
        /// The open conversation alone, as one opened in a window of its own on the Mac. Its list is kept for titles
        /// and for the viewer it becomes once the conversation closes, and isn't shown.
        case message
    }

    /// How far a narrow window's one stack goes. A wide window shows the mailboxes and the list side by side.
    public enum Depth: Equatable, Sendable {
        /// The list, and the conversation read over it.
        case list
        /// Back at the mailboxes, reading nothing, the list under them kept for a window that widens.
        case mailboxes
    }

    public init(
        list: List = .mailbox(.inbox), category: InboxCategory = .primary, filter: ListFilter = .none,
        depth: Depth = .list
    ) {
        self.list = list
        self.category = category
        self.filter = filter
        self.depth = depth
    }

    /// Reads `reading` over the list, in place of any conversation read before. A conversation reads over the list, so
    /// a narrow window is no longer back at the mailboxes.
    public mutating func read(_ reading: Reading) {
        self.reading = reading
        depth = .list
    }

    /// Reads nothing. A message window, which shows only its conversation, becomes a viewer.
    public mutating func closeReader() {
        reading = nil
        layout = .viewer
    }

    /// A narrow window is back at the mailboxes: it reads nothing, and keeps its list for when it widens.
    public mutating func backToMailboxes() {
        closeReader()
        depth = .mailboxes
    }

    /// A new window that reads `reading`. It keeps this window's list when that is where the conversation reads; one
    /// found elsewhere, such as in search, opens over its own mailbox. `layout` says whether the new window is the
    /// whole viewer or the conversation alone.
    public func opening(_ reading: Reading, as layout: Layout = .viewer) -> WindowState {
        var opened = self
        if list.readingMailbox != reading.mailbox { opened.list = .mailbox(reading.mailbox) }
        opened.read(reading)
        return opened.laidOut(as: layout)
    }

    /// This state laid out as `layout`, or as a viewer when it asks for a message window reading nothing.
    public func laidOut(as layout: Layout) -> WindowState {
        var laidOut = self
        laidOut.layout = reading == nil ? .viewer : layout
        return laidOut
    }
}
