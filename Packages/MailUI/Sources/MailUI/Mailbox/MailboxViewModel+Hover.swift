import MailCore

extension MailboxViewModel {
    /// The quick actions for a row under the pointer: the swipe buttons of both sides, as the reader arranged them.
    func hoverActions(for thread: ThreadSummary) -> [SwipeButton] {
        guard actions != nil else { return [] }
        return Preferences.swipeArrangement.hoverButtons(
            for: thread, at: ThreadPlace(thread, in: mailbox), tints: Preferences.swipeTints)
    }
}
