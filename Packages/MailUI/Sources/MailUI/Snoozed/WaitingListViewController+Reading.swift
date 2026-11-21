public import MailCore

/// Snoozed, as the window reads through it: a conversation read from it and put away goes on to the next snoozed one
/// (R7).
extension WaitingListViewController: ThreadSequence where Model == SnoozedViewModel {
    public var frontRows: [ThreadSummary.ID] { viewModel.listed.map(\.id) }

    public var frontMailbox: Mailbox { SnoozedViewModel.readingMailbox }

    public var pointerPick: [ThreadSummary.ID] { [] }

    public var frontSearching: Bool { false }

    public func summary(of thread: ThreadSummary.ID) -> ThreadSummary? {
        viewModel.listed.first { $0.id == thread }
    }

    public func mark(reading thread: ThreadSummary.ID?) {
        markRead(thread)
    }
}
