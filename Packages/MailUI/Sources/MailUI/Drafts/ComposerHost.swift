/// Keeps composers that are minimized, so several messages can be in progress at once, and moves them on and off the
/// screen.
protocol ComposerHost: AnyObject {
    /// The composer asks to move down to the bar, keeping what was written; `next` runs once it's there.
    func minimize(_ composer: ComposeViewController, then next: (() -> Void)?)
    /// The composer's message was sent, deleted, saved to Drafts or closed unchanged, so it is no longer in progress.
    func composerDidClose(_ composer: ComposeViewController)
}
