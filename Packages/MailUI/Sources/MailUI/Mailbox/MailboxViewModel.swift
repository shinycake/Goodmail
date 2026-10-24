import Foundation
import MailCore
import Observation

/// One mailbox list: the threads grouped into time sections, and the refresh state.
@Observable
public final class MailboxViewModel {
    public struct Section: Identifiable, Equatable {
        public let id: TimeSection
        public let title: String
        public let threads: [ThreadSummary]
    }

    public private(set) var sections: [Section] = []
    public private(set) var isRefreshing = false
    /// Whether older threads are being fetched for the bottom of the list.
    public private(set) var isLoadingOlder = false
    /// A refresh failure, for a quiet inline notice. Cleared by the next successful refresh.
    public private(set) var refreshError: (any Error)?
    public let accountColors: [AccountID: AccountColor]
    public let actions: MailActions?
    public let mailbox: Mailbox
    public let title: String
    /// The account new messages come from: the first one, until the composer offers a choice.
    @ObservationIgnored private let composingAccount: AccountID?

    @ObservationIgnored private let threads: () -> AsyncThrowingStream<[ThreadSummary], any Error>
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
        threads: @escaping () -> AsyncThrowingStream<[ThreadSummary], any Error>,
        refresh: @escaping () async throws -> Void,
        loadOlder: @escaping () async throws -> Bool = { false },
        navigate: @escaping (Route) -> Void = { _ in },
        actions: MailActions? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.actions = actions
        self.mailbox = mailbox
        self.title = title ?? mailbox.title(labels: [])
        composingAccount = accounts.first?.id
        accountColors = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.color) })
        self.threads = threads
        refreshAction = refresh
        loadOlderAction = loadOlder
        self.navigate = navigate
        self.now = now
        self.calendar = calendar
    }

    /// Follows the store until the calling task is cancelled.
    public func observe() async {
        do {
            for try await threads in threads() {
                let now = now()
                sections = TimeSection.group(threads, by: \.date, now: now, calendar: calendar).map {
                    Section(id: $0.section, title: $0.section.title(now: now, calendar: calendar), threads: $0.items)
                }
                // A list too short to scroll never nears its end, so fetch older mail now: Spam and Trash start
                // empty, and a quiet label may hold only a few threads in the window.
                if threads.count < Self.shortList { Task { await loadOlderIfNeeded() } }
            }
        } catch {
            refreshError = error
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
        navigate(.thread(id))
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

    /// The toolbar's actions for the threads selected in edit mode: their reading state, then what takes all of
    /// them out of the way here.
    static func bulkActions(for threads: [ThreadSummary]) -> [ThreadAction] {
        guard let first = threads.first else { return [] }
        let common = threads.dropFirst().reduce(Self.trailingActions(for: first)) { common, thread in
            let theirs = Self.trailingActions(for: thread)
            return common.filter(theirs.contains)
        }
        return [.markRead(threads.contains(where: \.isUnread))] + common
    }

    public func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) {
        actions?.perform(action, on: threads)
    }

    public func dateText(for thread: ThreadSummary) -> String {
        RowDate.text(for: thread.date, now: now(), calendar: calendar)
    }
}
