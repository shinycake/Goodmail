/// One window's navigation: what it shows (`state`), and the one transition every way it moves goes through
/// (`handle(_:in:)`). Routes, a conversation found or missing, Back, a change the reader asks of mail, Undo, other
/// accounts and lists, and Handoff are each an `Event`; the transition changes `state` and says what the window does
/// beyond showing it (`Effect`), such as looking a conversation up, presenting a screen or beginning search. The
/// window's screens then show `state` as it is (`stack`, or `list` and `reading` side by side), so nothing on screen keeps its own idea of what is
/// read.
///
/// It also keeps what the window must remember to move as the reader expects: the conversation opened and the rows it
/// was opened from, so one whose row has left since still has a next one (R7); what the reader last left, a conversation
/// or a pointer's pick, so Undo can bring the reader back to it until the window moves on by any other way (R9); and the conversation a
/// lookup is under way for, whose answer counts only while the window hasn't moved since.
public struct WindowNavigation: Equatable, Sendable {
    /// What the window shows and what it remembers of how it got there, which change together (`Course`).
    var course: Course
    /// When a list the state names, missing from the device, counts as gone.
    private(set) var listCheck: WindowState.ListCheck

    /// A window showing `state`, saved on this device or handed off from another as `lists` says.
    public init(showing state: WindowState, checking lists: WindowState.ListCheck = .saved) {
        course = Course(showing: state)
        listCheck = lists
    }

    /// What the window shows.
    public var state: WindowState { course.state }
    /// The conversation a lookup is under way for, where the route reads it, and where the route came from.
    public var pending: Awaited? { course.lookUp }
    /// What the reader last left by a change they asked, a conversation or a pointer's pick, until the window moves on
    /// by any other way.
    var departure: Departure? { course.wayBack }
    /// The conversation read, as it was opened.
    var opened: Opened? { course.opened }
    /// The change that took the conversation read out of the mailbox it is read in and left the reader reading it, as
    /// unstarring in Starred (R8), so the store then showing it gone from there doesn't close it (`Event.placed`),
    /// until Undo takes the change back.
    var kept: MailChange? { course.kept }

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
        /// The accounts whose Inbox isn't sorted into categories, so all of it is in Primary.
        public var unsortedInboxes: Set<AccountID>

        public init(
            arrangement: Arrangement, afterRemoval: AfterRemoval = .standard, unsortedInboxes: Set<AccountID> = []
        ) {
            self.arrangement = arrangement
            self.afterRemoval = afterRemoval
            self.unsortedInboxes = unsortedInboxes
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
        /// The window was asked to go somewhere, by its own screens unless `source` says otherwise.
        case route(Route, from: RouteSource = .window)
        /// The window comes up for `route`, from outside, over the state it restored, before any screen is built: a
        /// restored conversation the route doesn't open closes at once, so its reader isn't built under the new one.
        case launched(for: Route)
        /// The conversation a `.lookUp` asked for, as `summary`, from a list showing `rows`, search's results over it
        /// while `searching`. It counts only while that lookup is the one under way.
        case found(ThreadSummary, rows: [ThreadSummary.ID], searching: Bool = false)
        /// The conversation isn't on the device: the one a `.lookUp` asked for, which then opens nothing, or the one
        /// read, as one restored that was deleted meanwhile or whose reader can't be made, which closes. A message
        /// window becomes a viewer.
        case missing(ThreadSummary.ID)
        /// The conversation read is still on the device, as `summary`, as the window comes up or is rebuilt with what it
        /// read: its reader is made from this row rather than a read of the store on the main actor.
        case restored(ThreadSummary)
        /// The conversation a `.lookUp` asked for isn't on the device, and its service couldn't be asked, as offline.
        /// It opens nothing; for an arrival the window shows the Inbox and says so.
        case unreachable(ThreadSummary.ID)
        /// The reader went back by the stack's Back button or its edge swipe.
        case back(to: Back)
        /// The reader asked `change` of some conversations, with `reader` on show and `front` the list on show.
        case changed(MailChange, reader: Reader?, front: Front?)
        /// Undo took `change` back, with the list on show now listing `rows`, search's results over it while
        /// `searching`.
        case undone(MailChange, rows: [ThreadSummary.ID], searching: Bool = false)
        /// The store shows whether the mailbox `thread` is read in holds it, as its reader opens and each time that
        /// changes. Taken out by a change from outside the window, as another device, an alert action or a rule, its
        /// reader closes, so the list beside it never says that mailbox is empty while the reader still shows one of
        /// its conversations; the reader's own change that kept them reading it keeps it (R8), until the store shows it
        /// back. A message window, which shows nothing else, keeps it too.
        case placed(ThreadSummary.ID, inMailbox: Bool)
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
        /// Next or Previous Conversation, through `front`, the list on show.
        case step(Step, front: Front?)

        /// Whether the window moves by itself for this, rather than as the reader moved it by a tap, a click or Back,
        /// which VoiceOver follows on its own: after an action or Undo, a step to the next or previous conversation,
        /// which puts a reader in another's place, or the conversation read leaving from outside, so VoiceOver is
        /// told of it.
        public var movesByItself: Bool {
            switch self {
            case .changed, .undone, .step, .placed: true
            case .route, .launched, .found, .restored, .missing, .unreachable, .back, .accounts, .lists, .handedOff,
                .category, .filter:
                false
            }
        }
    }

    /// What the window does beyond showing `state`.
    public enum Effect: Equatable, Sendable {
        /// Clears what covers the window for an arrival from outside, before the effects after it (R3): Settings and
        /// the sheets that only read or pick go, the message being written goes down to the drafts pill, and search
        /// and Select mode end. An alert, a confirmation, a sign-in, a transfer or the accounts offer stays, and the
        /// arrival lands beneath it.
        case uncover
        /// Finds the conversation, to answer with `.found` or `.missing`.
        case lookUp(ThreadSummary.ID)
        /// Presents a screen over or beside the window. Nothing the window shows changes.
        case present(Presentation)
        /// Begins search over the list with `query` in its field.
        case beginSearch(SearchQuery)
        /// Shows the list's column, as after a mailbox was picked in a sidebar that covers it.
        case showList
        /// Counts the rows picked with a pointer beside the list: none, or several.
        case showPicked(Int)
        /// Picks these rows of the list on show again, top to bottom, as Undo brings them back: several picked with a
        /// pointer that an action put away.
        case repick([ThreadSummary.ID])
        /// A message window, which shows nothing else, goes once the change that took its conversation can't be
        /// undone (ADR-035).
        case leaveWindow
        /// Tells the reader something the window can't show, without stopping them (R10).
        case say(Notice)
    }

    /// What the window tells the reader when it can't show what was asked.
    public enum Notice: Equatable, Sendable {
        /// The conversation an arrival asked for isn't on the device, nor with its service.
        case conversationGone
        /// The conversation an arrival asked for isn't on the device yet, and its service can't be reached now.
        case conversationUnreachable
    }

    /// Moves the window for `event`, and says what it does beyond showing `state`.
    public mutating func handle(_ event: Event, in context: Context) -> [Effect] {
        switch event {
        case .route(let route, .window):
            return go(to: route, in: context)
        case .route(let route, .outside):
            return arrive(at: route, in: context)
        case .launched(let route):
            return launch(for: route, in: context)
        case .found(let summary, let rows, let searching):
            open(summary, from: rows, searching: searching, in: context)
        case .restored(let summary):
            restore(summary)
        case .missing(let thread):
            return missed(thread, in: context)
        case .unreachable(let thread):
            return unreached(thread, in: context)
        case .back(let back):
            goBack(to: back)
        case .changed(let change, let reader, let front):
            return asked(change, reader: reader, front: front, in: context)
        case .undone(let change, let rows, let searching):
            return undid(change, rows: rows, searching: searching)
        case .placed(let thread, let inMailbox):
            placed(thread, inMailbox: inMailbox)
        case .accounts(let accounts):
            // A lookup for an account that went is dropped; one for an account still here goes on, as one a window
            // coming up for an arrival started before its screens were built for the accounts (`launched`).
            if let pending, !accounts.contains(pending.reading.thread.accountID) { endLookUp() }
            show(state.keeping(accounts))
        case .lists(let lists, let accounts):
            // Only the viewer shows its list; a message window keeps reading where it was opened.
            guard state.layout == .viewer, let kept = listCheck.next(state, accounts: accounts, lists: lists)
            else { return [] }
            // An arrival looked up meanwhile, as at a cold launch over a list since deleted, still shows once found,
            // in a list that holds it.
            show(kept, awaiting: pending.flatMap { $0.source == .outside ? $0 : nil })
        case .handedOff(let handed, let accounts):
            showHandedOff(handed, accounts: accounts)
            // Handoff comes from outside, so it uncovers what it shows.
            return [.uncover]
        case .category(let category):
            var next = state
            next.category = category
            if next != state { next.closeReader() }
            move(to: next)
        case .filter(let filter):
            move { $0.filter = filter }
        case .step(let step, let front):
            take(step, in: front)
        }
        return []
    }

    /// The row of the conversation read, as the window found it or as Undo brings it back; `nil` when it reads none,
    /// or one it went on to from a list's rows or was restored with, which the screens find in the list or the store.
    public var foundRow: ThreadSummary? {
        opened?.row
    }

    /// The list a conversation opens from, as it shows now: its own rows, or search's over them while `searching`.
    func source(searching: Bool) -> Opened.From {
        Opened.From(list: state.list, searching: searching)
    }

    /// The rows the conversation read was opened from, while `front` is the list it was opened from as it shows now,
    /// which place it once its row has left; empty otherwise, as for rows another list or search showed.
    func trail(in front: Front?) -> [ThreadSummary.ID] {
        guard let opened, opened.from == source(searching: front?.searching ?? false) else { return [] }
        return opened.rows
    }

    /// Shows `next`, which differs from what shows by what is gone from the device: another list closes the reader,
    /// as every change of list does. A lookup `awaiting` goes on.
    private mutating func show(_ next: WindowState, awaiting: Awaited? = nil) {
        var next = next
        if next.list != state.list { next.closeReader() }
        move(to: next, awaiting: awaiting)
    }

    /// The store shows whether the mailbox `thread` is read in holds it. Out of it, the reader closes, unless the
    /// reader's own change kept them reading it there; back in it, nothing keeps it any more.
    private mutating func placed(_ thread: ThreadSummary.ID, inMailbox: Bool) {
        guard state.layout == .viewer, state.reading?.thread == thread else { return }
        if inMailbox {
            release()
        } else if kept == nil {
            move { $0.closeReader() }
        }
    }

    /// The conversation read is on the device as `summary`. Where it was opened from, and its trail, stay.
    private mutating func restore(_ summary: ThreadSummary) {
        guard state.reading?.thread == summary.id else { return }
        move(
            to: state,
            opening: Opened(from: opened?.from ?? source(searching: false), rows: opened?.rows ?? [], row: summary))
    }

    /// `thread` isn't on the device. The one read closes; one a route from inside asked for opens nothing, and one an
    /// arrival asked for is said to be gone, over the Inbox (R10).
    private mutating func missed(_ thread: ThreadSummary.ID, in context: Context) -> [Effect] {
        if let pending, pending.reading.thread == thread {
            endLookUp()
            if pending.source == .outside { return showInbox(saying: .conversationGone, in: context) }
        }
        if state.reading?.thread == thread { move { $0.closeReader() } }
        return []
    }

    /// `thread` isn't on the device and its service couldn't be asked. One a route from inside asked for opens
    /// nothing; one an arrival asked for is said to be out of reach, over the Inbox (R10).
    private mutating func unreached(_ thread: ThreadSummary.ID, in context: Context) -> [Effect] {
        guard let pending, pending.reading.thread == thread else { return [] }
        endLookUp()
        guard pending.source == .outside else { return [] }
        return showInbox(saying: .conversationUnreachable, in: context)
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
        let next =
            switch state.layout {
            case .viewer: kept.asViewer
            case .message: kept.asMessage ?? kept.asViewer
            }
        move(to: next)
        endLookUp()
        listCheck = .handedOff
    }
}
