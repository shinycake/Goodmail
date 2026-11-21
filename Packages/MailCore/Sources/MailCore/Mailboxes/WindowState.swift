/// What one window shows: the list beside the mailboxes, the Inbox's category and filter, and where the window is
/// (`Place`): back at the mailboxes, at the list with the conversation it reads, or one conversation alone. The scene
/// coordinator keeps it in step as the reader moves, rebuilds either arrangement from it when the window changes width
/// (`stack`, `columns`), and saves it so the system can restore the window or hand it off to another device
/// (`WindowState+Coding`).
public struct WindowState: Equatable, Sendable {
    /// The list beside the mailboxes. It says nothing of what is read, which is `place`'s.
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

    /// Where the window is, and the conversation it reads there. A message window always reads one, and a narrow
    /// window back at the mailboxes reads none.
    public enum Place: Hashable, Sendable {
        /// A narrow window back at the mailboxes, reading nothing. The list stays for when the window widens. Not
        /// saved: a restored or handed-off window opens on its list.
        case mailboxes
        /// The viewer: the mailboxes, the list and the conversation read from it, if one is, as many of them as the
        /// window's width holds.
        case list(reading: Reading?)
        /// A conversation alone, as one opened in a window of its own on the Mac. The list is kept for titles and for
        /// the viewer the window becomes once the conversation closes, and isn't shown.
        case message(Reading)
    }

    /// What a window lays out around what it shows: the whole viewer, or one conversation alone (`Place.message`).
    public enum Layout: String, Equatable, Codable, Sendable {
        case viewer
        case message
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
    public var place: Place

    public init(
        list: List = .mailbox(.inbox), category: InboxCategory = .primary, filter: ListFilter = .none,
        place: Place = .list(reading: nil)
    ) {
        self.list = list
        self.category = category
        self.filter = filter
        self.place = place
    }

    /// The conversation the window reads, and where; `nil` with none open.
    public var reading: Reading? {
        switch place {
        case .mailboxes: nil
        case .list(let reading): reading
        case .message(let reading): reading
        }
    }

    public var layout: Layout {
        switch place {
        case .mailboxes, .list: .viewer
        case .message: .message
        }
    }

    /// Reads `reading` in place of any conversation read before: alone in a message window, else over the list, so a
    /// narrow window is no longer back at the mailboxes.
    public mutating func read(_ reading: Reading) {
        switch place {
        case .mailboxes, .list: place = .list(reading: reading)
        case .message: place = .message(reading)
        }
    }

    /// Reads nothing. A message window, which shows only its conversation, becomes a viewer.
    public mutating func closeReader() {
        switch place {
        case .mailboxes: break
        case .list, .message: place = .list(reading: nil)
        }
    }

    /// A narrow window is back at the mailboxes: it reads nothing, and keeps its list for when it widens.
    public mutating func backToMailboxes() {
        place = .mailboxes
    }

    /// A new window that reads `reading`. It keeps this window's list when that is where the conversation reads; one
    /// found elsewhere, such as in search, opens over its own mailbox. `layout` says whether the new window is the
    /// whole viewer or the conversation alone.
    public func opening(_ reading: Reading, as layout: Layout = .viewer) -> WindowState {
        var opened = self
        if list.readingMailbox != reading.mailbox { opened.list = .mailbox(reading.mailbox) }
        opened.place =
            switch layout {
            case .viewer: .list(reading: reading)
            case .message: .message(reading)
            }
        return opened
    }

    /// This state as the whole viewer: a message window's conversation reads over its list.
    public var asViewer: WindowState {
        var viewer = self
        if case .message(let reading) = place { viewer.place = .list(reading: reading) }
        return viewer
    }

    /// This state as a message window reading its conversation alone; `nil` when it reads none.
    public var asMessage: WindowState? {
        guard let reading else { return nil }
        var message = self
        message.place = .message(reading)
        return message
    }
}
