import Foundation
public import MailCore
public import Observation

/// Threads snoozed out of the Inbox, soonest to come back first.
@Observable
public final class SnoozedViewModel: WaitingListModel {
    /// What the store last said: not read yet, or the snoozed threads, soonest back first. The rows and the
    /// conversations the window reads on through are both read from it.
    private enum Snoozed {
        case loading
        case loaded([SnoozedThread])
    }

    private var snoozed = Snoozed.loading

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

    public var content: WaitingContent<ThreadSummary.ID> {
        switch snoozed {
        case .loading: .loading
        case .loaded(let threads): .loaded(threads.map(row(for:)))
        }
    }

    /// The snoozed conversations as listed, soonest back first, for the window to read on through them. Observed, so
    /// the reader's chevrons follow it (`StepChevrons`).
    var listed: [ThreadSummary] {
        switch snoozed {
        case .loading: []
        case .loaded(let threads): threads.map(\.thread)
        }
    }

    /// Follows the store until the calling task is cancelled. A failure leaves the last list in place.
    public func observe() async {
        do {
            for try await threads in threads() {
                snoozed = .loaded(threads)
            }
        } catch {}
    }

    /// Where a snoozed conversation is read: out of the Inbox, so in All Mail.
    static let readingMailbox = Mailbox.allMail

    /// Reads the thread; it stays snoozed.
    public func open(_ id: ThreadSummary.ID) {
        navigate(.thread(id, in: Self.readingMailbox))
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
                ? String(
                    localized: "No Subject", table: "Snoozed", bundle: .module,
                    comment: "Shown for a message without a subject")
                : thread.subject,
            time: ScheduledTime.text(for: snoozed.wakeAt),
            accountColor: accounts.count > 1 ? accounts.first { $0.id == thread.id.accountID }?.color : nil)
    }
}
