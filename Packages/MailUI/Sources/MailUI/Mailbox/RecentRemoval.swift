import MailCore

/// Whether the rows that last left a list were ones the reader had just taken away, which tells an Inbox the reader
/// cleared from one that emptied some other way (`InboxZeroArrival`).
nonisolated enum RecentRemoval: Equatable, Sendable {
    /// They left some other way, as by sync, or none has left yet.
    case none
    /// They left at `at`, taken away by what the reader had asked just before.
    case took(at: ContinuousClock.Instant)
    /// The list switched category and the new one's first answer isn't on screen yet: rows that leave until it is
    /// are the last category's going, whatever the reader asked meanwhile.
    case switching

    /// How long after the reader asks a change its rows still count as taken away by it when they leave.
    static let window: Duration = .seconds(3)

    /// After the rows of `left`, as they were listed in `mailbox`, left the list at `now`, with `answered` saying
    /// whether the rows now shown are the store's answer for the list's category. `asked` is the last change the reader
    /// asked, and when, whatever screen asked it. It took them only if it was about some of them and takes them out of
    /// the mailbox: starring or marking read leaves a row where it is, so a sync that then takes it doesn't count.
    mutating func rowsLeft(
        _ left: [ThreadSummary], answered: Bool, in mailbox: Mailbox,
        asked: (change: MailChange, at: ContinuousClock.Instant)?, at now: ContinuousClock.Instant
    ) {
        // The rows that leave as the new category's first answer goes on screen are the last category's, as are any
        // that leave before it, as when a flight into a box ends.
        if case .switching = self {
            if answered { self = .none }
            return
        }
        guard !left.isEmpty else { return }
        guard let asked, now - asked.at <= Self.window else {
            self = .none
            return
        }
        let threads = Set(asked.change.threads)
        let took = left.contains { thread in
            threads.contains(thread.id) && Self.takesOut(asked.change.request, thread, of: mailbox)
        }
        self = took ? .took(at: now) : .none
    }

    /// Whether `request` takes `thread` out of `mailbox`.
    private static func takesOut(_ request: MailChange.Request, _ thread: ThreadSummary, of mailbox: Mailbox) -> Bool {
        switch request {
        case .action(let action):
            switch action.outcome(for: thread.labelIDs) {
            case .deleted: true
            case .labeled(let labels): !mailbox.contains(labels: labels)
            }
        case .move, .snooze, .unsnooze, .block: true
        }
    }
}
