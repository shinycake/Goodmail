import Foundation
import MailCore
import Observation

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

/// One mailbox list: the threads grouped into time sections, and the refresh state.
@Observable
public final class MailboxViewModel {
    public struct Section: Identifiable, Equatable {
        public let id: TimeSection
        public let title: String
        public let threads: [ThreadSummary]
    }

    public private(set) var sections: [Section] = []
    /// Whether the store has answered at least once, so an empty list means an empty mailbox.
    public private(set) var hasLoaded = false
    public private(set) var isRefreshing = false
    /// Whether older threads are being fetched for the bottom of the list.
    public private(set) var isLoadingOlder = false
    /// A refresh failure, for a quiet inline notice. Cleared by the next successful refresh.
    public private(set) var refreshError: (any Error)?
    /// The account's color in one account's mailbox; the combined theme in one that spans them.
    public let theme: Theme
    @ObservationIgnored private let accounts: [AccountID: Account]
    /// Each account's service, which decides the actions its threads have.
    var services: [AccountID: MailService] { accounts.mapValues(\.service) }
    public let actions: MailActions?
    public let mailbox: Mailbox
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
        refresh: @escaping () async throws -> Void,
        loadOlder: @escaping () async throws -> Bool = { false },
        navigate: @escaping (Route) -> Void = { _ in },
        actions: MailActions? = nil,
        combinedTheme: CombinedTheme = Preferences.combinedTheme,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.actions = actions
        self.mailbox = mailbox
        self.title = title ?? mailbox.title(labels: [])
        composingAccount = mailbox.accountID ?? accounts.first?.id
        theme = Theme(accountID: mailbox.accountID, among: accounts, combined: combinedTheme)
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        self.source = source
        refreshAction = refresh
        loadOlderAction = loadOlder
        self.navigate = navigate
        self.now = now
        self.calendar = calendar
    }

    /// Follows the store until the calling task is cancelled.
    public func observe() async {
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

    private func followUnreadCounts(_ categories: InboxCategories) async {
        do {
            for try await counts in categories.unreadCounts() { categoryUnreadCounts = counts }
        } catch {
            if !Task.isCancelled { refreshError = error }
        }
    }

    private func follow(_ threads: AsyncThrowingStream<[ThreadSummary], any Error>) async {
        do {
            for try await threads in threads {
                // A list replaced by another category's may still hand over one last value.
                if Task.isCancelled { return }
                hasLoaded = true
                let now = now()
                sections = TimeSection.group(threads, by: \.date, now: now, calendar: calendar).map {
                    Section(id: $0.section, title: $0.section.title(now: now, calendar: calendar), threads: $0.items)
                }
                // A list too short to scroll never nears its end, so fetch older mail now: Spam and Trash start
                // empty, and a quiet label may hold only a few threads in the window. Not for one category: older
                // pages are the whole Inbox's, and Forums may stay short however many of them come.
                if case .flat = source, threads.count < Self.shortList { Task { await loadOlderIfNeeded() } }
            }
        } catch {
            if !Task.isCancelled { refreshError = error }
        }
    }

    /// Below this many threads, the list fetches older ones without waiting for a scroll.
    static let shortList = 30

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await refreshAction()
            refreshError = nil
        } catch {
            refreshError = error
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

    /// The swipe actions for a row, edge-most first: reading state and star from the leading edge; from the
    /// trailing one, what takes the thread out of the way here.
    func swipeActions(for thread: ThreadSummary, leading: Bool) -> [ThreadAction] {
        guard actions != nil else { return [] }
        if leading {
            return [.markRead(thread.isUnread), .star(!thread.labelIDs.contains(SystemLabel.starred))]
        }
        return Self.trailingActions(for: thread)
    }

    /// What takes `thread` out of the way, by where it is: out of Trash, out of Spam, or out of the Inbox.
    static func trailingActions(for thread: ThreadSummary) -> [ThreadAction] {
        if thread.labelIDs.contains(SystemLabel.trash) { return [.untrash] }
        if thread.labelIDs.contains(SystemLabel.spam) { return [.moveToInbox, .trash] }
        return thread.labelIDs.contains(SystemLabel.inbox) ? [.archive, .trash] : [.trash]
    }

    /// The toolbar's actions for the threads selected in edit mode: their reading state, what takes all of them out
    /// of the way here, then Mute or Unmute when all of them allow it.
    static func bulkActions(for threads: [ThreadSummary], services: [AccountID: MailService]) -> [ThreadAction] {
        guard let first = threads.first else { return [] }
        let common = threads.dropFirst().reduce(Self.trailingActions(for: first)) { common, thread in
            let theirs = Self.trailingActions(for: thread)
            return common.filter(theirs.contains)
        }
        return [.markRead(threads.contains(where: \.isUnread))] + common
            + [muting(threads, services: services)].compactMap(\.self)
    }

    /// Mute or Unmute, when every thread is in an account whose service has it and all of them allow it.
    private static func muting(_ threads: [ThreadSummary], services: [AccountID: MailService]) -> ThreadAction? {
        let known = threads.compactMap { thread in services[thread.id.accountID].map { (thread.labelIDs, $0) } }
        return known.count == threads.count ? ThreadAction.muting(known) : nil
    }

    /// Whether the threads can be snoozed together: only threads in the Inbox can, since snoozing takes them out
    /// of it.
    static func canSnooze(_ threads: [ThreadSummary]) -> Bool {
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
