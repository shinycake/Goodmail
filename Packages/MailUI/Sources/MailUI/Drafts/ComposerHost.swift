/// Keeps composers that are minimized, so several messages can be in progress at once, and moves them on and off the
/// screen.
protocol ComposerHost: AnyObject {
    /// Whether a message here can be minimized; not in a window of its own, which is its own place.
    var canMinimize: Bool { get }
    /// Whether the composer's window closes it with the window's own close button, so the composer shows none of its
    /// own: a window of its own on the Mac, with its traffic lights.
    var closesWithWindow: Bool { get }
    /// The composer asks to move down into the drafts pill, keeping what was written; `next` runs once it's there.
    func minimize(_ composer: ComposeViewController, then next: (() -> Void)?)
    /// The composer kept its message as written, as autosave does after each edit: what the host keeps of it, to
    /// bring back after the app is closed or crashes, follows.
    func composerKept(_ composer: ComposeViewController)
    /// The composer's message was sent, deleted, saved to Drafts or closed unchanged, so it is no longer in progress.
    func composerDidClose(_ composer: ComposeViewController)
}
