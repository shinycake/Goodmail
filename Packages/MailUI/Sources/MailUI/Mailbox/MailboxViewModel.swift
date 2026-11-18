public import Foundation
public import MailCore
import OSLog
public import Observation

/// What a mailbox list shows: one list of threads, or the Inbox split into Gmail's categories with one of them shown.
public enum MailboxSource {
    case flat(() -> AsyncThrowingStream<[ThreadSummary], any Error>)
    case categorised(InboxCategories, selected: InboxCategory)
}

/// Where the Inbox's categories come from: the threads under one, and the unread counts for the menu.
public struct InboxCategories {
    let threads: (InboxCategory) -> AsyncThrowingStream<[ThreadSummary], any Error>
    let unreadCounts: () -> AsyncThrowingStream<[InboxCategory: Int], any Error>
    /// Told of each category the reader picks, so a rebuilt list can open on it.
    let didSelect: (InboxCategory) -> Void

    public init(
        threads: @escaping (InboxCategory) -> AsyncThrowingStream<[ThreadSummary], any Error>,
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
    /// Whether the store has answered at least once, so an empty list means an empty mailbox.
    public private(set) var hasLoaded = false
    public private(set) var isRefreshing = false
    /// Whether older threads are being fetched for the bottom of the list.
    public private(set) var isLoadingOlder = false
    /// The sync problems of this mailbox's accounts that need the reader, in the accounts' order.
    public var problems: [AccountProblemNotice] { health.notices(for: mailboxAccounts) }
    /// The account's color in one account's mailbox; the combined theme in one that spans them.
    public let theme: Theme
    @ObservationIgnored private let accounts: [AccountID: Account]
    /// The accounts whose threads this mailbox lists, in their order.
    @ObservationIgnored private let mailboxAccounts: [Account]
    @ObservationIgnored private let health: AccountHealthBoard
    public let actions: MailActions?
    public let mailbox: Mailbox
    /// Whether this is a Trash, of every account or of one, which Delete Forever can empty.
    var isTrash: Bool { mailbox.labelID == SystemLabel.trash }
    public let title: String
    /// The category the list shows, or `nil` when the mailbox isn't split into categories.
    public var category: InboxCategory? {
        guard case .categorised(_, let selected) = source else { return nil }
        return selected
    }
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
    /// The latest of each stream `sections` is made from.
    @ObservationIgnored private var listed: [ThreadSummary] = []
    @ObservationIgnored private var woken: [ThreadSummary.ID: Date] = [:]
    @ObservationIgnored private var pinned: Set<ThreadSummary.ID> = []
    @ObservationIgnored private let refreshAction: () async throws -> Void
    @ObservationIgnored private let loadOlderAction: () async throws -> Bool
    @ObservationIgnored private let navigate: (Route) -> Void
    @ObservationIgnored private var mayHaveOlder = true
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(
        mailbox: Mailbox = .inbox,
        title: String? = nil,
        accounts: [Account],
        source: MailboxSource,
        woken: (() -> AsyncThrowingStream<[ThreadSummary.ID: Date], any Error>)? = nil,
        pins: (() -> AsyncThrowingStream<Set<ThreadSummary.ID>, any Error>)? = nil,
        refresh: @escaping () async throws -> Void,
        loadOlder: @escaping () async throws -> Bool = { false },
        navigate: @escaping (Route) -> Void = { _ in },
        actions: MailActions? = nil,
        health: AccountHealthBoard = AccountHealthBoard(),
        combinedTheme: CombinedTheme = Preferences.combinedTheme,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.actions = actions
        self.mailbox = mailbox
        self.title = title ?? mailbox.listTitle(labels: [], accounts: accounts)
        composingAccount = mailbox.accountID ?? accounts.first?.id
        theme = Theme(accountID: mailbox.accountID, among: accounts, combined: combinedTheme)
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        mailboxAccounts = accounts.filter { mailbox.accountID == nil || mailbox.accountID == $0.id }
        self.health = health
        self.source = source
        wokenThreads = woken
        pinnedThreads = pins
        refreshAction = refresh
        loadOlderAction = loadOlder
        self.navigate = navigate
        self.now = now
        self.calendar = calendar
    }

    /// Follows the store until the calling task is cancelled.
    public func observe() async {
        async let woken: Void = followWoken()
        async let pins: Void = followPins()
        await followSource()
        await woken
        await pins
    }

    private func followSource() async {
        switch source {
        case .flat(let threads):
            await follow(threads())
        case .categorised(let categories, _):
            async let counts: Void = followUnreadCounts(categories)
            // Each selection replaces the list it follows.
            var following: Task<Void, Never>?
            for await case let category? in Observations({ self.category }) {
                following?.cancel()
                following = Task { await follow(categories.threads(category)) }
            }
            following?.cancel()
            await counts
        }
    }

    /// Shows the threads under `category`.
    public func select(_ category: InboxCategory) {
        guard case .categorised(let categories, let selected) = source, category != selected else { return }
        source = .categorised(categories, selected: category)
        categories.didSelect(category)
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

    private func followUnreadCounts(_ categories: InboxCategories) async {
        do {
            for try await counts in categories.unreadCounts() { categoryUnreadCounts = counts }
        } catch {
            Self.log.error("The category counts stopped: \(error, privacy: .public)")
        }
    }

    private func follow(_ threads: AsyncThrowingStream<[ThreadSummary], any Error>) async {
        do {
            for try await threads in threads {
                // A list replaced by another category's may still hand over one last value.
                if Task.isCancelled { return }
                hasLoaded = true
                listed = threads
                regroup()
                // A list too short to scroll never nears its end, so fetch older mail now: Spam and Trash start
                // empty, and a quiet label may hold only a few threads in the window. Not for one category: older
                // pages are the whole Inbox's, and Forums may stay short however many of them come.
                if case .flat = source, threads.count < Self.shortList { Task { await loadOlderIfNeeded() } }
            }
        } catch {
            Self.log.error("The list stopped: \(error, privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "mailbox")

    /// Pinned threads first, newest on top, then threads back from snooze, latest woken on top, then the rest by
    /// time.
    private func regroup() {
        let now = now()
        let pinned = listed.filter { self.pinned.contains($0.id) }
        let unpinned = listed.filter { !self.pinned.contains($0.id) }
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
    }

    /// Below this many threads, the list fetches older ones without waiting for a scroll.
    static let shortList = 30

    /// Syncs now. A failure is the health board's to tell, as the sync reports it there.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        try? await refreshAction()
    }

    /// What a notice's button does: the service's sign-in for a sign-in it turned down, a sync now for the rest.
    public func fix(_ notice: AccountProblemNotice) async {
        switch notice.problem {
        case .signInRejected: navigate(.signInAgain(notice.account.id))
        case .cantSync: await refresh()
        }
    }

    /// Call as the list nears its end. Fetches one older page at a time until the provider has no more.
    /// A failure is quiet: the next approach to the end tries again.
    public func loadOlderIfNeeded() async {
        guard mayHaveOlder, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            mayHaveOlder = try await loadOlderAction()
        } catch {
            mayHaveOlder = true
        }
    }

    public func compose() {
        guard let composingAccount else { return }
        navigate(.compose(Draft(accountID: composingAccount)))
    }

    public func open(_ id: ThreadSummary.ID) {
        navigate(.thread(id, in: mailbox))
    }

    public func openInNewWindow(_ id: ThreadSummary.ID) {
        navigate(.newWindow(id, in: mailbox))
    }

    /// The window `id` opens in when its row is dragged out of the list: this list, on the category it shows, with
    /// the thread open.
    func newWindow(for id: ThreadSummary.ID) -> WindowState {
        WindowState(list: .mailbox(mailbox, thread: id), category: category ?? .primary)
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
    func swipeActions(for thread: ThreadSummary, leading: Bool) -> [SwipeButton] {
        guard actions != nil else { return [] }
        return Preferences.swipeArrangement.buttons(
            for: thread, at: ThreadPlace(thread, in: mailbox), on: leading ? .leading : .trailing,
            tints: Preferences.swipeTints)
    }

    /// The toolbar's actions for the threads of `mailbox` selected in edit mode: their reading state, what takes all
    /// of them out of the way here, then Mute or Unmute when all of them allow it.
    static func bulkActions(for threads: [ThreadSummary], in mailbox: Mailbox) -> [ThreadAction] {
        guard let first = threads.first else { return [] }
        let common = threads.dropFirst().reduce(ThreadPlace(first, in: mailbox).awayActions) { common, thread in
            let theirs = ThreadPlace(thread, in: mailbox).awayActions
            return common.filter(theirs.contains)
        }
        return [.markRead(threads.contains(where: \.isUnread))] + common
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
