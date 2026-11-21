/// Every place the app can navigate to (ADR-011). Notifications, intents, Spotlight and the UI all produce these,
/// and the scene coordinator is the only thing that acts on them.
public enum Route: Hashable, Sendable {
    /// A thread, read from `mailbox`, which a move takes it out of.
    case thread(ThreadSummary.ID, in: Mailbox)
    /// No thread beside the list, which has `count` of its threads picked with a pointer: none, or several, which the
    /// pane counts.
    case selection(count: Int)
    /// A thread in a window of its own, read from `mailbox`, where the device has more than one window.
    case newWindow(ThreadSummary.ID, in: Mailbox)
    /// One mailbox's thread list.
    case mailbox(Mailbox)
    /// The composer, with a new message, reply or forward.
    case compose(Draft)
    /// The composer, finishing the draft that is a thread's newest message, which may still have to be fetched; the
    /// thread itself when its newest message is no draft.
    case draft(ThreadSummary.ID)
    /// The composer, answering a thread's newest message, which may still have to be fetched.
    case answer(ThreadSummary.ID, Answer)
    /// The label picker for these threads, which share one account.
    case changeLabels([ThreadSummary.ID])
    /// Where to move these threads, which the reader sees in `mailbox`.
    case move([ThreadSummary.ID], from: Mailbox)
    /// Search over the shown mailbox's list, or the Inbox's, with `query` in the field: ready to type in when it is
    /// empty, showing its results otherwise.
    case search(SearchQuery)
    /// The messages waiting to be sent later.
    case scheduled
    /// The threads snoozed out of the Inbox until later.
    case snoozed
    /// A smart mailbox's conversations (ADR-039).
    case smartMailbox(SmartMailbox.ID)
    /// The smart mailbox editor with a new box holding what `query` finds, or a blank one for an empty query.
    case newSmartMailbox(SearchQuery)
    /// The smart mailbox editor, changing a box.
    case editSmartMailbox(SmartMailbox.ID)
    /// Accounts and preferences, open at `page`.
    case settings(SettingsPage)
    /// The account's sign-in, again, after its service turned the stored one down: its web page, or its password.
    case signInAgain(AccountID)
}

/// Where Settings opens.
public enum SettingsPage: Hashable, Sendable {
    /// Its first screen.
    case main
    /// The swipe actions, as from a swipe button touched and held.
    case swipeActions
}
