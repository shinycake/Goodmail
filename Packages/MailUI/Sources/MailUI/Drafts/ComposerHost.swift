/// Keeps composers that are minimized, so several messages can be in progress at once, and moves them on and off the
/// screen.
protocol ComposerHost: AnyObject {
    /// Whether a message here can be minimized; not in a window of its own, which is its own place.
    var canMinimize: Bool { get }
    /// The composer asks to move down to the bar, keeping what was written; `next` runs once it's there.
    func minimize(_ composer: ComposeViewController, then next: (() -> Void)?)
    /// The composer's message was sent, deleted, saved to Drafts or closed unchanged, so it is no longer in progress.
    func composerDidClose(_ composer: ComposeViewController)
    /// The composer is about to put the keyboard away at once, as its card sets off: the host may keep a picture of
    /// it to travel with the card.
    func keyboardWillLeave(_ composer: ComposeViewController)
}

extension ComposerHost {
    func keyboardWillLeave(_ composer: ComposeViewController) {}
}
