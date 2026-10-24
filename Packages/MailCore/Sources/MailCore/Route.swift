/// Every place the app can navigate to (ADR-011). Notifications, intents, Spotlight and the UI all produce these,
/// and the scene coordinator is the only thing that acts on them.
public enum Route: Hashable, Sendable {
    case thread(ThreadSummary.ID)
    /// One mailbox's thread list.
    case mailbox(Mailbox)
    /// The composer, with a new message, reply or forward.
    case compose(Draft)
    /// The label picker for these threads, which share one account.
    case changeLabels([ThreadSummary.ID])
    /// Accounts and preferences.
    case settings
}
