/// Keeps composers that are minimized, so several messages can be in progress at once.
protocol ComposerHost: AnyObject {
    /// The composer moved out of the way, keeping what was written, to be opened again later.
    func composerDidMinimize(_ composer: ComposeViewController)
    /// The composer's message was sent, deleted, saved to Drafts or closed unchanged, so it is no longer in progress.
    func composerDidClose(_ composer: ComposeViewController)
}
