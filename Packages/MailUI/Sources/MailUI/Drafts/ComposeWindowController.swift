public import UIKit

/// Fills a window that holds one message (`ComposeWindow`): the composer, as in the sheet, across the whole window.
/// The message can't be minimized here, since the window is its own place; it closes the window once it is sent,
/// deleted or saved away.
public final class ComposeWindowController: UINavigationController, ComposerHost {
    private let kept: () -> Void
    private let closed: () -> Void

    /// `kept` runs each time the message is kept as written, `closed` once the message is done with.
    public init(composer: ComposeViewController, kept: @escaping () -> Void = {}, closed: @escaping () -> Void) {
        self.kept = kept
        self.closed = closed
        super.init(rootViewController: composer)
        composer.host = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// The message being written, as written so far.
    public var composer: ComposeViewController? { viewControllers.first as? ComposeViewController }

    var canMinimize: Bool { false }

    func minimize(_ composer: ComposeViewController, then next: (() -> Void)?) {
        next?()
    }

    func composerKept(_ composer: ComposeViewController) {
        kept()
    }

    func composerDidClose(_ composer: ComposeViewController) {
        closed()
    }
}
