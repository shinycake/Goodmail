/// One window's navigation: what it shows (`state`), and the one transition every way it moves goes through
/// (`handle(_:in:)`). Routes, a conversation found or missing, Back, a change the reader asks of mail, Undo, other
/// accounts and lists, and Handoff are each an `Event`; the transition changes `state` and says what the window does
/// beyond showing it (`Effect`), such as looking a conversation up, presenting a screen or beginning search. The
/// window's screens then show `state` as it is (`stack`, `columns`), so nothing on screen keeps its own idea of what is
/// read.
///
/// It also keeps what the window must remember to move as the reader expects: the rows a conversation was opened from,
/// so one whose row has left since still has a next one (R7), and the conversation the reader last left, so Undo can
/// bring the reader back to it until the window moves on by any other way (R9).
public struct WindowNavigation: Equatable, Sendable {
    /// What the window shows.
    public internal(set) var state: WindowState
    /// The row of the conversation read, as the window found it, so its reader is made without reading the store.
    var found: ThreadSummary?
    /// The list's rows when the conversation read opened.
    var trail: Trail?
    /// The conversation the reader last left by a change they asked, until the window moves on by any other way.
    var departure: Departure?
    /// When a list the state names, missing from the device, counts as gone.
    var listCheck: WindowState.ListCheck

    /// A window showing `state`, saved on this device or handed off from another as `lists` says.
    public init(showing state: WindowState, checking lists: WindowState.ListCheck = .saved) {
        self.state = state
        listCheck = lists
    }

    /// How the window lays out what it shows: one narrow stack, or a wide window's columns.
    public enum Arrangement: Equatable, Sendable {
        case stack
        case columns
    }

    /// What the window knows as an event comes, apart from what it shows.
    public struct Context: Equatable, Sendable {
        public var arrangement: Arrangement
        /// Where the reader goes after putting the conversation on show away, read as each change is asked.
        public var afterRemoval: AfterRemoval

        public init(arrangement: Arrangement, afterRemoval: AfterRemoval = .standard) {
            self.arrangement = arrangement
            self.afterRemoval = afterRemoval
        }
    }

    /// Where Back went.
    public enum Back: Equatable, Sendable {
        /// From the reader to the list.
        case list
        /// From the list to the mailboxes, in a narrow window.
        case mailboxes
    }

    /// Something that moves the window, or may.
    public enum Event: Equatable, Sendable {
        /// The window was asked to go somewhere.
        case route(Route)
        /// The conversation a `.lookUp` asked for, as `summary`, to read in `mailbox`, from a list showing `rows`.
        case found(ThreadSummary, in: Mailbox, rows: [ThreadSummary.ID])
        /// The conversation isn't on the device: one a `.lookUp` asked for, or the one read, as one restored or handed
        /// off that was deleted meanwhile, which closes. A message window becomes a viewer.
        case missing(ThreadSummary.ID)
        /// The reader went back by the stack's Back button or its edge swipe.
        case back(to: Back)
        /// The reader asked `change` of some conversations, with `reader` on show and `front` the list on show.
        case changed(MailChange, reader: Reader?, front: Front?)
        /// Undo took `change` back, with the list on show now listing `rows`.
        case undone(MailChange, rows: [ThreadSummary.ID])
        /// The accounts on the device are now `accounts`.
        case accounts([AccountID])
        /// The labels and smart mailboxes on the device are now `lists`, of `accounts`.
        case lists(WindowState.OwnLists, accounts: [AccountID])
        /// Another device handed off `state`, for the accounts here, `accounts`.
        case handedOff(WindowState, accounts: [AccountID])
        /// The Inbox shows another category.
        case category(InboxCategory)
        /// The list is filtered by `filter`.
        case filter(ListFilter)
        /// Search began or ended over the list, so the rows the reader goes on in changed.
        case searchToggled
    }

    /// What the window does beyond showing `state`.
    public enum Effect: Equatable, Sendable {
        /// Finds the conversation, to answer with `.found` or `.missing`.
        case lookUp(ThreadSummary.ID, in: Mailbox)
        /// Presents what `route` names over or beside the window: the composer, a picker, Settings, a sign-in, the
        /// smart mailbox editor, another window. Nothing the window shows changes.
        case present(Route)
        /// Begins search over the list with `query` in its field.
        case beginSearch(SearchQuery)
        /// Shows the list's column, as after a mailbox was picked in a sidebar that covers it.
        case showList
        /// Counts the rows picked with a pointer beside the list: none, or several.
        case showPicked(Int)
        /// A message window, which shows nothing else, goes once the change that took its conversation can't be
        /// undone (ADR-035).
        case leaveWindow
    }

    /// Moves the window for `event`, and says what it does beyond showing `state`.
    public mutating func handle(_ event: Event, in context: Context) -> [Effect] {
        switch event {
        case .route(let route):
            return go(to: route, in: context)
        case .found(let summary, let mailbox, let rows):
            open(summary, in: mailbox, from: rows)
            return []
        case .missing(let thread):
            if state.reading?.thread == thread { move { $0.closeReader() } }
            return []
        case .back(let back):
            goBack(to: back)
            return []
        case .changed(let change, let reader, let front):
            return asked(change, reader: reader, front: front, in: context)
        case .undone(let change, let rows):
            undid(change, rows: rows)
            return []
        case .accounts(let accounts):
            move { $0 = $0.keeping(accounts) }
            return []
        case .lists(let lists, let accounts):
            // Only the viewer shows its list; a message window keeps reading where it was opened.
            guard state.layout == .viewer, let kept = listCheck.next(state, accounts: accounts, lists: lists)
            else { return [] }
            move { $0 = kept }
            return []
        case .handedOff(let handed, let accounts):
            showHandedOff(handed, accounts: accounts)
            return []
        case .category(let category):
            move { $0.category = category }
            return []
        case .filter(let filter):
            move { $0.filter = filter }
            return []
        case .searchToggled:
            departure = nil
            return []
        }
    }

    /// The row of the conversation read, as the window found it or as Undo brings it back; `nil` when it reads none,
    /// or one it went on to from a list's rows or was restored with, which the screens find in the list or the store.
    public var foundRow: ThreadSummary? {
        guard let found, found.id == state.reading?.thread else { return nil }
        return found
    }

    /// Changes what the window shows by any way but the reader's own course. When anything changed, Undo has nowhere
    /// to bring the reader back to (R9).
    mutating func move(_ change: (inout WindowState) -> Void) {
        let before = state
        change(&state)
        if state != before { departure = nil }
    }

    /// Back went to `back`: the list stays for a window that widens.
    private mutating func goBack(to back: Back) {
        guard state.layout == .viewer else { return }
        switch back {
        case .list: move { $0.closeReader() }
        case .mailboxes: move { $0.backToMailboxes() }
        }
    }

    /// Shows what another device handed off laid out as this window is: a viewer stays a viewer, and a message window
    /// reads the handed-off conversation alone, or becomes a viewer when nothing is read. Its list may not be synced
    /// here yet, so a missing one waits for the lists here to change before it gives way.
    private mutating func showHandedOff(_ handed: WindowState, accounts: [AccountID]) {
        let kept = handed.keeping(accounts)
        let laidOut =
            switch state.layout {
            case .viewer: kept.asViewer
            case .message: kept.asMessage ?? kept.asViewer
            }
        self = WindowNavigation(showing: laidOut, checking: .handedOff)
    }
}
