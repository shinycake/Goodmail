public import UIKit

/// Fills a window that holds one message (`ComposeWindow`): the composer, as in the sheet, across the whole window.
/// The message can't be minimized here, since the window is its own place; it closes the window once it is sent,
/// deleted or saved away.
public final class ComposeWindowController: UINavigationController, ComposerHost {
    private let kept: () -> Void
    private let closed: () -> Void
    /// What runs once the composer is first on screen, as what was dropped on a mail window for it going in. Only the
    /// first appearance takes it.
    private var onScreen: (() -> Void)?

    /// `kept` runs each time the message is kept as written, `closed` once the message is done with, and `onScreen`
    /// once the composer is first on screen.
    public init(
        composer: ComposeViewController, kept: @escaping () -> Void = {}, closed: @escaping () -> Void,
        onScreen: (() -> Void)? = nil
    ) {
        self.kept = kept
        self.closed = closed
        self.onScreen = onScreen
        super.init(rootViewController: composer)
        composer.host = self
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let first = onScreen
        onScreen = nil
        first?()
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
