public import UIKit

/// Fills a window that holds one message (`ComposeWindow`): the composer, as in the sheet, across the whole window.
/// The message can't be minimized here, since the window is its own place; it closes the window once it is sent,
/// deleted or saved away.
public final class ComposeWindowController: UINavigationController, ComposerHost {
    private let kept: () -> Void
    private let closed: () -> Void
    /// Where the window's app opens new messages: in a window of their own, as on the Mac, the window closes the message
    /// with its own close button.
    private let placement: ComposePlacement
    /// What runs once the composer is first on screen, as what was dropped on a mail window for it going in. Only the
    /// first appearance takes it.
    private var onScreen: (() -> Void)?

    /// `placement` is where the window opens new messages. `kept` runs each time the message is kept as written,
    /// `closed` once the message is done with, and `onScreen` once the composer is first on screen.
    public init(
        composer: ComposeViewController, placement: ComposePlacement, kept: @escaping () -> Void = {},
        closed: @escaping () -> Void, onScreen: (() -> Void)? = nil
    ) {
        self.kept = kept
        self.closed = closed
        self.placement = placement
        self.onScreen = onScreen
        super.init(rootViewController: composer)
        composer.host = self
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The window is the message's place to rest, as the sheet's card landing is: writing starts in its field.
        composer?.didOpen()
        let first = onScreen
        onScreen = nil
        first?()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// The message being written, as written so far.
    public var composer: ComposeViewController? { viewControllers.first as? ComposeViewController }

    var canMinimize: Bool { false }

    var closesWithWindow: Bool {
        switch placement {
        // A message moved out of a mail window on iPad, whose window has no close button of its own.
        case .sheet: false
        case .ownWindow: true
        }
    }

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
