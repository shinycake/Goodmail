public import Foundation
public import MailCore
import OSLog
public import Observation

/// What a mailbox list shows: one list of threads, or the Inbox split into Gmail's categories with one of them shown.
public enum MailboxSource {
    case flat(ThreadSource)
    case categorised(InboxCategories, selected: InboxCategory)
}

/// Where one list's threads come from.
public enum ThreadSource {
    /// A mailbox, read a window at a time (ADR-046).
    case windowed((ThreadWindow) -> AsyncThrowingStream<ThreadListing, any Error>)
    /// A list read whole, as search's results and a smart mailbox's, which hold only what they match.
    case whole(() -> AsyncThrowingStream<[ThreadSummary], any Error>)
}

/// Where the Inbox's categories come from: the threads under one, a window at a time, and the unread counts for the
/// menu.
public struct InboxCategories {
    let threads: (InboxCategory, ThreadWindow) -> AsyncThrowingStream<ThreadListing, any Error>
    let unreadCounts: () -> AsyncThrowingStream<[InboxCategory: Int], any Error>
    /// Told of each category the reader picks, so a rebuilt list can open on it.
    let didSelect: (InboxCategory) -> Void

    public init(
        threads: @escaping (InboxCategory, ThreadWindow) -> AsyncThrowingStream<ThreadListing, any Error>,
        unreadCounts: @escaping () -> AsyncThrowingStream<[InboxCategory: Int], any Error>,
        didSelect: @escaping (InboxCategory) -> Void = { _ in }
    ) {
        self.threads = threads
        self.unreadCounts = unreadCounts
        self.didSelect = didSelect
    }
}

/// A part of a mailbox list: pinned threads at the top, then threads just back from snooze, then the time sections.
nonisolated public enum MailboxSection: Hashable, Sendable {
    case pinned
    case backFromSnooze
    case time(TimeSection)
}

/// One mailbox list: the threads grouped into time sections, and the refresh state.
@Observable
public final class MailboxViewModel {
    public struct Section: Identifiable, Equatable {
        public let id: MailboxSection
        public let title: String
        public let threads: [ThreadSummary]
    }

    public private(set) var sections: [Section] = []
    /// Whether the store has answered for what the list shows, and with threads. Only `follow`, `select` and
    /// `moveWindow` change it.
    private(set) var listing = Listing.waiting(showing: ThreadListing(whole: []))
    /// How much of the mailbox the list reads. Only `moveWindow` changes it.
    private(set) var window: ListWindow
    /// Whether a sync the list asked for is under way.
    public var isRefreshing: Bool { syncing != nil }
    /// The sync the list asked for, which a second ask joins rather than starting another. Only `sync()` changes it.
    private var syncing: Task<Void, Never>?
    /// The registration with the relay that fixing paused alerts asked for. Only `registerAgain()` changes it.
    @ObservationIgnored private var registering: Task<Void, Never>?
    /// Where fetching older threads for the bottom of the list stands. Only `loadOlder` changes it.
    private(set) var older = OlderPages.mayHaveMore
    /// What an empty list means now.
    var emptyListing: EmptyListing {
        // Older pages are the whole Inbox's, not one category's, so a category's list never waits on them.
        guard case .flat = source, case .fetching = older else { return EmptyListing(listing, paging: false) }
        return EmptyListing(listing, paging: true)
    }
    /// The sync problems of this mailbox's accounts that need the reader, in the accounts' order.
    public var problems: [AccountProblemNotice] { health.notices(for: mailboxAccounts) }
    /// The account's color in one account's mailbox; the combined theme in one that spans them.
    public let theme: Theme
    @ObservationIgnored let accounts: [AccountID: Account]
    /// The accounts whose threads this mailbox lists, in their order.
    @ObservationIgnored private let mailboxAccounts: [Account]
    @ObservationIgnored private let health: AccountHealthBoard
    public let actions: MailActions?
    /// Apply Rules, Block Sender and VIPs, where the app offers them.
    let senders: SenderRules?
    /// Where a dragged conversation's files come from, in a desktop window; `nil` where none are made.
    let conversationSources: ConversationSources?
    public let mailbox: Mailbox
    /// Whether this is a Trash, of every account or of one, which Delete Forever can empty.
    var isTrash: Bool { mailbox.labelID == SystemLabel.trash }
    /// The list's name, which a label's list learns off the main actor once it is built (`naming`).
    public private(set) var title: String
    /// Names the list from the store off the main actor, as a label's list needs its label's name; `nil` when it
    /// knows its name already.
    public typealias Naming = @concurrent @Sendable () async -> String?
    @ObservationIgnored private let naming: Naming?
    /// The category the list shows, or `nil` when the mailbox isn't split into categories.
    public var category: InboxCategory? {
        guard case .categorised(_, let selected) = source else { return nil }
        return selected
    }
    /// What the list is filtered by, and what was read under it on this visit, which stays listed (`isShown`).
    var visit: FilterVisit
    /// What the list is filtered by. Only `setFilter` changes it.
    public internal(set) var filter: ListFilter {
        get { visit.filter }
        set { visit.filter(by: newValue, reading: reading) }
    }
    /// How many threads the filter leaves out of what the store listed, so an empty list can tell a filter that hides
    /// everything from a mailbox with nothing in it.
    public private(set) var hiddenByFilter = 0
    /// Whether the list can be filtered: the window keeps the filter (`didChangeFilter`).
    var offersFilter: Bool { didChangeFilter != nil }
    /// What the list has picked, with the rows a conversation read was picked from. Only `pick` changes it; the ways
    /// to pick are in `MailboxViewModel+Selection`.
    private(set) var listPick = ListPick()
    public var selection: ListSelection { listPick.selection }
    /// How the list's window is driven: whether a pick opens what it reads (`pick`).
    let interaction: InteractionStyle
    /// Unread threads per category, for the menu; categories with none are left out.
    public private(set) var categoryUnreadCounts: [InboxCategory: Int] = [:]
    /// The account new messages come from: the mailbox's own, or the first one in a mailbox spanning accounts.
    @ObservationIgnored private let composingAccount: AccountID?

    /// Changed only by `select`.
    private var source: MailboxSource
    /// Threads put back by their snooze, with when they woke; the ones in this list lead it.
    @ObservationIgnored private let wokenThreads: (() -> AsyncThrowingStream<[ThreadSummary.ID: Date], any Error>)?
    /// The pinned threads, which lead the list above all others; `nil` for a list that shows no pins.
    @ObservationIgnored private let pinnedThreads: (() -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>)?
    /// The latest of each stream `sections` is made from, with `listing`'s threads.
    @ObservationIgnored private var woken: [ThreadSummary.ID: Date] = [:]
    @ObservationIgnored private var pinned: Set<ThreadSummary.ID> = []
    @ObservationIgnored private let refreshAction: () async throws -> Void
    @ObservationIgnored private let retryAlerts: () async -> Void
    @ObservationIgnored private let olderThreads: OlderThreads
    @ObservationIgnored private let navigate: (Route) -> Void
    /// Told of each filter the reader picks, so a rebuilt list opens with it; `nil` for a list that isn't filtered.
    @ObservationIgnored let didChangeFilter: ((ListFilter) -> Void)?
    /// The threads that hold files among those downloaded, which With Attachments needs; `nil` where it can't be asked.
    @ObservationIgnored let attachmentThreads: (() -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>)?
    /// The sidebar's model, which ⌘1 to ⌘9 and ⌃⌘1 to ⌃⌘9 ask for the rows; `nil` where this list has none beside it.
    @ObservationIgnored let sidebar: () -> MailboxesViewModel?
    /// Whether the list follows which threads hold files, and what it heard. Only `watchAttachments` changes it.
    @ObservationIgnored var attachmentWatch = AttachmentWatch.off
    @ObservationIgnored private let readAheadAction: (ThreadFetcher.Request) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(
        mailbox: Mailbox = .inbox,
        title: String? = nil,
        naming: Naming? = nil,
        accounts: [Account],
        source: MailboxSource,
        woken: (() -> AsyncThrowingStream<[ThreadSummary.ID: Date], any Error>)? = nil,
        pins: (() -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>)? = nil,
        filter: ListFilter = .none,
        didChangeFilter: ((ListFilter) -> Void)? = nil,
        attachmentThreads: (() -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>)? = nil,
        sidebar: @escaping () -> MailboxesViewModel? = { nil },
        refresh: @escaping () async throws -> Void,
        retryAlerts: @escaping () async -> Void = {},
        older: OlderThreads = .pages { false },
        navigate: @escaping (Route) -> Void = { _ in },
        readAhead: @escaping (ThreadFetcher.Request) -> Void = { _ in },
        actions: MailActions? = nil,
        senders: SenderRules? = nil,
        conversationSources: ConversationSources? = nil,
        interaction: InteractionStyle = .touch,
        health: AccountHealthBoard = AccountHealthBoard(),
        combinedTheme: CombinedTheme = Preferences.combinedTheme,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.actions = actions
        self.senders = senders
        self.conversationSources = conversationSources
        self.interaction = interaction
        self.mailbox = mailbox
        self.title = title ?? mailbox.listTitle(labels: [], accounts: accounts)
        self.naming = naming
        composingAccount = mailbox.accountID ?? accounts.first?.id
        theme = Theme(accountID: mailbox.accountID, among: accounts, combined: combinedTheme)
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        mailboxAccounts = accounts.filter { mailbox.accountID == nil || mailbox.accountID == $0.id }
        self.health = health
        self.source = source
        wokenThreads = woken
        pinnedThreads = pins
        visit = FilterVisit(filter)
        window = ListWindow(windowed: source.isWindowed, needs: filter.isOn ? [.filter] : [])
        self.didChangeFilter = didChangeFilter
        self.attachmentThreads = attachmentThreads
        self.sidebar = sidebar
        refreshAction = refresh
        self.retryAlerts = retryAlerts
        olderThreads = older
        self.navigate = navigate
        readAheadAction = readAhead
        self.now = now
        self.calendar = calendar
    }

    /// Follows the store until the calling task is cancelled.
    public func observe() async {
        async let woken: Void = followWoken()
        async let pins: Void = followPins()
        async let attachments: Void = followAttachments()
        async let named: Void = followName()
        await followSource()
        await woken
        await pins
        await attachments
        await named
    }

    private func followName() async {
        guard let naming, let name = await naming() else { return }
        title = name
    }

    private func followSource() async {
        // A list read whole has no window to change, so it follows its one stream to the end.
        if case .flat(.whole(let threads)) = source {
            return await follow(threads().map(ThreadListing.init(whole:)), for: ask)
        }
        async let counts: Void = followUnreadCounts()
        // Each category and each window replaces the stream before it.
        var following: Task<Void, Never>?
        var followed: ListAsk?
        for await ask in Observations({ self.ask }) where ask != followed {
            followed = ask
            following?.cancel()
            following = follow(ask)
        }
        following?.cancel()
        await counts
    }

    /// Follows what the store lists for `ask`, until the task it returns is cancelled.
    private func follow(_ ask: ListAsk) -> Task<Void, Never> {
        switch source {
        case .flat(.windowed(let threads)):
            let listings = threads(ask.window)
            return Task { await follow(listings, for: ask) }
        case .flat(.whole(let threads)):
            let listings = threads().map(ThreadListing.init(whole:))
            return Task { await follow(listings, for: ask) }
        case .categorised(let categories, let selected):
            let listings = categories.threads(selected, ask.window)
            return Task { await follow(listings, for: ask) }
        }
    }

    /// Shows the threads under `category`.
    public func select(_ category: InboxCategory) {
        guard case .categorised(let categories, let selected) = source, category != selected else { return }
        source = .categorised(categories, selected: category)
        listing = listing.waiting
        moveWindow { $0.restart() }
        visit.restart(reading: reading)
        categories.didSelect(category)
    }

    /// The one place `window` changes, by one of its transitions. A window that asks the store for other threads waits
    /// for their answer, still showing the rows it has, so nothing reads the last window's answer as this one's.
    func moveWindow(_ change: (inout ListWindow) -> Void) {
        var moved = window
        change(&moved)
        guard moved != window else { return }
        if moved.asked != window.asked { listing = listing.waiting }
        window = moved
    }

    /// Another category with unread mail, for an empty list to point to.
    public var categoryWithUnread: InboxCategory? {
        guard let category else { return nil }
        return InboxCategory.allCases.first { $0 != category && categoryUnreadCounts[$0, default: 0] > 0 }
    }

    private func followWoken() async {
        guard let wokenThreads else { return }
        do {
            for try await woken in wokenThreads() {
                self.woken = woken
                regroup()
            }
        } catch {}
    }

    private func followPins() async {
        guard let pinnedThreads else { return }
        do {
            for try await pinned in pinnedThreads() {
                self.pinned = pinned
                regroup()
            }
        } catch {}
    }

    private func followUnreadCounts() async {
        guard case .categorised(let categories, _) = source else { return }
        do {
            for try await counts in categories.unreadCounts() { categoryUnreadCounts = counts }
        } catch {
            Self.log.error("The category counts stopped: \(error, privacy: .private)")
        }
    }

    /// Follows what the store lists for `ask`.
    private func follow(_ listings: some AsyncSequence<ThreadListing, any Error>, for ask: ListAsk) async {
        do {
            for try await listed in listings {
                // A list replaced by another category's or window's may still hand over a value, until it is
                // cancelled once the change is seen.
                if Task.isCancelled || ask != self.ask { return }
                // An answer that changes nothing, as the store gives after a page whose threads don't show here,
                // asks for no further page: that would ask again after every page, for ever.
                let changed = !listing.hasAnswered || listed != listing.shown
                listing = listing.answered(listed)
                regroup()
                if changed { fetchOlderWhileShort() }
            }
        } catch {
            Self.log.error("The list stopped: \(error, privacy: .private)")
        }
    }

    private static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "mailbox")

    /// Pinned threads first, newest on top, then threads back from snooze, latest woken on top, then the rest by
    /// time. Threads the store held below the window show only in the first two, while the pins and snoozes say they
    /// belong there: the time sections are the window's alone.
    func regroup() {
        let now = now()
        let before = rows
        let listed = listing.threads
        let kept = listed.filter(isShown)
        hiddenByFilter = listed.count - kept.count
        // Below every thread in the window, so they keep the list's order after it.
        let held = listing.held.filter { (self.pinned.contains($0.id) || woken[$0.id] != nil) && isShown($0) }
        let pinned = (kept + held).filter { self.pinned.contains($0.id) }
        let unpinned = (kept + held).filter { !self.pinned.contains($0.id) }
        let back = unpinned.compactMap { thread in woken[thread.id].map { (thread, $0) } }
            .sorted { $0.1 > $1.1 }.map(\.0)
        let rest = unpinned.filter { woken[$0.id] == nil }
        let leading = [
            Section(
                id: .pinned,
                title: String(localized: "Pinned", table: "Pin", bundle: .module, comment: "Mailbox section header"),
                threads: pinned),
            Section(
                id: .backFromSnooze,
                title: String(
                    localized: "Back from snooze", table: "Mailbox", bundle: .module, comment: "Mailbox section header"),
                threads: back),
        ]
        sections =
            leading.filter { !$0.threads.isEmpty }
            + TimeSection.group(rest, by: \.date, now: now, calendar: calendar).map {
                Section(id: .time($0.section), title: $0.section.title(now: now, calendar: calendar), threads: $0.items)
            }
        pickAfterRowsChanged(from: before)
    }

    /// Below this many threads, the list fetches older ones without waiting for a scroll.
    static let shortList = 30

    /// Syncs now. A failure is the health board's to tell, as the sync reports it there.
    public func refresh() async {
        await sync().value
    }

    /// Syncs now, for Get Mail and pull to refresh. The sync is every account's, not this list's, so it runs to its end
    /// even when the reader picks another mailbox and this list goes.
    public func getMail() {
        _ = sync()
    }

    /// The sync under way, or a new one.
    private func sync() -> Task<Void, Never> {
        if let syncing { return syncing }
        let task = Task { [weak self, refreshAction] in
            try? await refreshAction()
            self?.syncing = nil
        }
        syncing = task
        return task
    }

    /// What a notice's button does: the service's sign-in for a sign-in it turned down, a sync now for one that
    /// can't sync, and registering with the relay again for paused alerts, which has it try the login once more.
    /// Returns the work it started, if any: like a sync, the model's own, which runs to its end when the list goes.
    @discardableResult
    public func fix(_ notice: AccountProblemNotice) -> Task<Void, Never>? {
        switch notice.problem {
        case .signInRejected:
            navigate(.signInAgain(notice.account.id))
            return nil
        case .cantSync: return sync()
        case .alertsPaused: return registerAgain()
        }
    }

    /// The registration with the relay under way, or a new one, which a second ask joins as with `sync()`.
    private func registerAgain() -> Task<Void, Never> {
        if let registering { return registering }
        let task = Task { [weak self, retryAlerts] in
            await retryAlerts()
            self?.registering = nil
        }
        registering = task
        return task
    }

    /// A list too short to scroll never nears its end, so fetch older mail now: Spam and Trash start empty, and a quiet
    /// label may hold only a few threads in the window. Not for one category: older pages are the whole Inbox's, and
    /// Forums may stay short however many of them come. Called in the same step as the store's answer, so an empty
    /// list is never seen waiting for a fetch that hasn't begun.
    ///
    /// It asks only after an answer that changes the list, so the asking can't go on for ever. The price: after a fetch
    /// that failed, as offline, a short list that never changes asks again only on the store's next real change or a
    /// scroll near its end, not by itself once the network is back.
    private func fetchOlderWhileShort() {
        guard case .flat = source, listing.reach == .whole, listing.threads.count < Self.shortList else { return }
        loadOlder()
    }

    /// Call as the list nears its end, and wait for the page to come. See `loadOlder`.
    public func loadOlderIfNeeded() async {
        await loadOlder()?.value
    }

    /// Call as the list nears its end. Starts fetching one older page, unless one is on its way, which this joins, or
    /// there are no more. A failure is quiet: the next approach to the end tries again. The page is the mailbox's, not
    /// this list's, so like a sync it runs to its end even when the list goes; `older` holds it until then.
    @discardableResult
    func loadOlder() -> Task<Void, Never>? {
        switch older {
        case .exhausted: return nil
        case .fetching(let fetch): return fetch
        case .mayHaveMore: break
        }
        let fetch: Task<Void, Never>
        switch olderThreads {
        case .pages(let next):
            let listedBefore = listing.threads.count
            fetch = Task { [weak self] in
                do {
                    let more = try await next()
                    guard let self else { return }
                    older = more ? .mayHaveMore : .exhausted
                    // The store may have answered for the page before it came, finding this fetch still on its way
                    // and joining it: ask again while the list grows. A page that adds nothing here, as one whose
                    // threads an action still in the outbox takes away, stops it, so the asking can't go on forever.
                    if listing.threads.count > listedBefore { fetchOlderWhileShort() }
                } catch {
                    // The next approach to the end, or the store's next answer, asks again.
                    self?.older = .mayHaveMore
                }
            }
        case .owned(let hasMore, let next):
            guard hasMore() else { return nil }
            fetch = Task { [weak self] in
                try? await next()
                self?.older = .mayHaveMore
            }
        }
        older = .fetching(fetch)
        return fetch
    }

    /// The one place `selection` changes. `revealing` is for a pick made with a pointer or keys, which the reader
    /// follows: it opens the thread being read, or counts several. Touch opens threads itself, as before.
    func pick(_ new: ListSelection, revealing: Bool) {
        guard new != selection else { return }
        listPick.pick(new, from: rows)
        // Select All keeps every thread listed only while several stay picked.
        if case .several(let ids, _) = new, !ids.isEmpty {} else { letGo(.selectAll) }
        if case .reading(let id) = new { visit.read(id) }
        guard revealing else { return }
        switch new {
        case .reading(let id): navigate(.thread(id, in: mailbox))
        case .several(let ids, _): navigate(.selection(count: ids.count))
        case .none: navigate(.selection(count: 0))
        }
    }

    public func compose() {
        guard let composingAccount else { return }
        navigate(.compose(Draft(accountID: composingAccount)))
    }

    public func open(_ id: ThreadSummary.ID) {
        navigate(.thread(id, in: mailbox))
    }

    /// Starts fetching threads' bodies before they open: their rows are coming up or showed, or the reader is
    /// touching one; nearest first.
    func readAhead(_ ids: [ThreadSummary.ID], because reason: ThreadFetcher.ReadAhead) {
        readAheadAction(.readAhead(ids, because: reason))
    }

    /// Drops threads whose rows scrolled away from reading ahead, unless their fetch began.
    func skipReadAhead(_ ids: [ThreadSummary.ID]) {
        readAheadAction(.skip(ids))
    }

    public func openInNewWindow(_ id: ThreadSummary.ID) {
        navigate(.newWindow(id, in: mailbox))
    }

    /// The window `id` opens in when its row is dragged out of the list: this list, on the category it shows, with
    /// the thread open.
    func newWindow(for id: ThreadSummary.ID) -> WindowState {
        WindowState(list: .mailbox(mailbox), category: category ?? .primary, filter: filter)
            .opening(Reading(id, in: mailbox))
    }

    /// What a swipe button does: act on the thread at once, or ask until when to snooze it.
    nonisolated enum Swipe: Equatable {
        case perform(ThreadAction)
        case snooze
    }

    /// A swipe button: the choice it stands for, what it does here, and what it wears.
    nonisolated struct SwipeButton: Equatable {
        let choice: SwipeChoice
        let swipe: Swipe
        let tint: SwipeTint
    }

    /// The swipe settings, as from a swipe button touched and held.
    func openSwipeSettings() {
        navigate(.settings(.swipeActions))
    }

    /// The swipe buttons for a row, edge-most first, as the reader arranged and tinted them.
    func swipeActions(for thread: ThreadSummary, on side: SwipeSide) -> [SwipeButton] {
        guard actions != nil else { return [] }
        return Preferences.swipeArrangement.buttons(
            for: thread, at: ThreadPlace(thread, in: mailbox), on: side,
            tints: Preferences.swipeTints)
    }

    /// The toolbar's actions for the threads of `mailbox` selected in edit mode: their reading state, what takes all
    /// of them out of the way here, then Mute or Unmute when all of them allow it.
    static func bulkActions(for threads: [ThreadSummary], in mailbox: Mailbox) -> [ThreadAction] {
        guard !threads.isEmpty else { return [] }
        return [.markRead(threads.contains(where: \.isUnread))]
            + ThreadPlace.awayActions(sharedBy: threads, in: mailbox)
            + [ThreadAction.muting(threads.map(\.labelIDs))].compactMap(\.self)
    }

    /// Whether the thread is pinned, or `nil` in a list that shows no pins, which offers neither Pin nor Unpin.
    func isPinned(_ thread: ThreadSummary.ID) -> Bool? {
        pinnedThreads == nil ? nil : pinned.contains(thread)
    }

    /// Pin for the threads unless all of them are pinned already, then Unpin; `nil` in a list that shows no pins.
    func pinning(_ threads: [ThreadSummary.ID]) -> Bool? {
        guard pinnedThreads != nil, !threads.isEmpty else { return nil }
        return !threads.allSatisfy(pinned.contains)
    }

    /// Pins the threads to the top of their lists, or with `pinned` false unpins them.
    public func pin(_ threads: [ThreadSummary.ID], _ pinned: Bool) {
        actions?.pin(threads, pinned)
    }

    /// Whether the threads can be snoozed together: only threads in the Inbox can, since snoozing takes them out
    /// of it.
    nonisolated static func canSnooze(_ threads: [ThreadSummary]) -> Bool {
        !threads.isEmpty && threads.allSatisfy { $0.labelIDs.contains(SystemLabel.inbox) }
    }

    /// Takes the threads out of the Inbox until `date`.
    public func snooze(_ threads: [ThreadSummary.ID], until date: Date) {
        actions?.snooze(threads, until: date)
    }

    /// Opens the places these threads can move to from this mailbox.
    public func move(_ threads: [ThreadSummary.ID]) {
        navigate(.move(threads, from: mailbox))
    }

    /// Opens the composer answering `thread`'s newest message.
    public func answer(_ thread: ThreadSummary.ID, with answer: Answer) {
        navigate(.answer(thread, answer))
    }

    /// Opens the label picker for these threads.
    public func changeLabels(of threads: [ThreadSummary.ID]) {
        navigate(.changeLabels(threads))
    }

    public func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) {
        actions?.perform(action, on: threads)
    }

    /// What `thread`'s row shows of its account, or `nil` while the account is gone.
    func rowAccount(for thread: ThreadSummary) -> RowAccount? {
        accounts[thread.id.accountID].map(theme.rowAccount)
    }

    public func dateText(for thread: ThreadSummary) -> String {
        RowDate.text(for: thread.date, now: now(), calendar: calendar)
    }
}
