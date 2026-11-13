/// Every place the app can navigate to (ADR-011). Notifications, intents, Spotlight and the UI all produce these,
/// and the scene coordinator is the only thing that acts on them.
public enum Route: Hashable, Sendable {
    /// A thread, read from `mailbox`, which a move takes it out of.
    case thread(ThreadSummary.ID, in: Mailbox)
    /// One mailbox's thread list.
    case mailbox(Mailbox)
    /// The composer, with a new message, reply or forward.
    case compose(Draft)
    /// The label picker for these threads, which share one account.
    case changeLabels([ThreadSummary.ID])
    /// Where to move these threads, which the reader sees in `mailbox`.
    case move([ThreadSummary.ID], from: Mailbox)
    /// The messages waiting to be sent later.
    case scheduled
    /// The threads snoozed out of the Inbox until later.
    case snoozed
    /// Accounts and preferences.
    case settings
}
