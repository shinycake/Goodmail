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

    @ObservationIgnored private let threads: () -> AsyncThrowingStream<[ThreadSummary], any Error>
    @ObservationIgnored private let refreshAction: () async throws -> Void
    @ObservationIgnored private let loadOlderAction: () async throws -> Bool
    @ObservationIgnored private let navigate: (Route) -> Void
    @ObservationIgnored private var mayHaveOlder = true
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(
        accounts: [Account],
        threads: @escaping () -> AsyncThrowingStream<[ThreadSummary], any Error>,
        refresh: @escaping () async throws -> Void,
        loadOlder: @escaping () async throws -> Bool = { false },
        navigate: @escaping (Route) -> Void = { _ in },
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
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
            }
        } catch {
            refreshError = error
        }
    }

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

    public func open(_ id: ThreadSummary.ID) {
        navigate(.thread(id))
    }

    public func dateText(for thread: ThreadSummary) -> String {
        RowDate.text(for: thread.date, now: now(), calendar: calendar)
    }
}
