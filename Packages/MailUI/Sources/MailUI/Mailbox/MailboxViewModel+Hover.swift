import MailCore

extension MailboxViewModel {
    /// The quick actions for a row under the pointer: the ones the reader picked for hovering, none while they're off.
    func hoverActions(for thread: ThreadSummary) -> [SwipeButton] {
        guard actions != nil else { return [] }
        return Preferences.hoverActions.buttons(
            for: thread, at: ThreadPlace(thread, in: mailbox), tints: Preferences.swipeTints)
    }
}
