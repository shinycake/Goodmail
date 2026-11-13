import Foundation
import MailCore
import Observation

/// Threads snoozed out of the Inbox, soonest to come back first.
@Observable
public final class SnoozedViewModel: WaitingListModel {
    public private(set) var content = WaitingContent<ThreadSummary.ID>.loading

    @ObservationIgnored private let threads: () -> AsyncThrowingStream<[SnoozedThread], any Error>
    @ObservationIgnored private let accounts: [Account]
    @ObservationIgnored private let actions: MailActions
    @ObservationIgnored private let navigate: (Route) -> Void

    public init(
        accounts: [Account], threads: @escaping () -> AsyncThrowingStream<[SnoozedThread], any Error>,
        actions: MailActions, navigate: @escaping (Route) -> Void
    ) {
        self.accounts = accounts
        self.threads = threads
        self.actions = actions
        self.navigate = navigate
    }

    /// Follows the store until the calling task is cancelled. A failure leaves the last list in place.
    public func observe() async {
        do {
            for try await threads in threads() { content = .loaded(threads.map(row(for:))) }
        } catch {}
    }

    /// Reads the thread; it stays snoozed.
    public func open(_ id: ThreadSummary.ID) {
        navigate(.thread(id, in: .allMail))
    }

    /// Puts the thread back in the Inbox now.
    public func takeBack(_ id: ThreadSummary.ID) {
        actions.unsnooze([id])
    }

    private func row(for snoozed: SnoozedThread) -> WaitingRow<ThreadSummary.ID> {
        let thread = snoozed.thread
        return WaitingRow(
            id: thread.id, title: thread.sender.displayName,
            subtitle: thread.subject.isEmpty
                ? String(localized: "No Subject", bundle: .module, comment: "Shown for a message without a subject")
                : thread.subject,
            time: ScheduledTime.text(for: snoozed.wakeAt),
            accountColor: accounts.count > 1 ? accounts.first { $0.id == thread.id.accountID }?.color : nil)
    }
}
