public import UIKit

/// A window's mail screens: mailboxes, a mailbox's list and a thread side by side when the window is wide, one
/// stack when it is narrow. The undo toast floats over them, above the toolbars, or
/// in the middle of a toolbar that leaves it room (`UndoToastLane`). Shaking to undo is
/// the window's (`ShakeToUndoWindow`), so that no screen holds first responder and raises the keyboard with a menu.
public final class MailSplitViewController: UISplitViewController {
    private let actions: MailActions
    private let toast = UndoToastView()
    private var shownToast: MailActions.Toast.ID?
    private var toastBottom: NSLayoutConstraint!

    public init(actions: MailActions) {
        self.actions = actions
        super.init(style: .tripleColumn)
        preferredSplitBehavior = .tile
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let haptics = HapticPlayer(view: view)
        actions.feedback = { haptics.play($0) }
        toast.alpha = 0
        toast.onUndo = { [weak self] in self?.actions.undoLast() }
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        toastBottom = toast.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            toastBottom,
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
        ])
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeToast()
    }

    private func placeToast() {
        view.bringSubviewToFront(toast)
        let size = toast.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let placement = UndoToastPlacement.choose(
            ends: toolbarEnds(), midX: view.bounds.midX, toastSize: size, aboveInset: aboveToolbars() + 12)
        let constant = placement.bottomConstant(in: view.bounds, toastHeight: size.height)
        if toastBottom.constant != constant { toastBottom.constant = constant }
    }

    /// How far the shown screens' content ends above the bottom: a screen's safe area ends above its toolbar when
    /// there is one, else above the home indicator.
    private func aboveToolbars() -> CGFloat {
        let insets = shownScreens.map(\.view.safeAreaInsets.bottom)
        return insets.max() ?? view.safeAreaInsets.bottom
    }

    /// The frames of the toolbar's end buttons, in this view's coordinates, when one screen fills the window and
    /// its toolbar's middle is open for the toast. Side by side, the toast stays centered on the window, not on one
    /// column's toolbar. The buttons' own frames, as the toolbar view's is the whole window on iOS 27. Search's item
    /// stands for a button the search controller draws, and reports an empty frame: the toast, centered, keeps the
    /// same room from both ends, so the buttons that do report one are enough.
    private func toolbarEnds() -> [CGRect] {
        guard isCollapsed, let lane = shownScreens.first as? any UndoToastLane,
            lane.navigationController?.isToolbarHidden == false
        else { return [] }
        return lane.toolbarEnds.compactMap { $0.frame(in: view) }.filter { !$0.isEmpty }
    }

    /// The screen on top in each shown column.
    private var shownScreens: [UIViewController] {
        let columns: [Column] = isCollapsed ? [.compact] : [.primary, .supplementary, .secondary]
        return columns.compactMap { column in
            let shown = viewController(for: column)
            let top = (shown as? UINavigationController)?.topViewController ?? shown
            guard let top, top.view.window != nil else { return nil }
            return top
        }
    }

    /// Called by UIKit whenever the observed toast changes.
    public override func updateProperties() {
        super.updateProperties()
        let current = actions.toast
        guard current?.id != shownToast else { return }
        shownToast = current?.id
        if let current {
            toast.show(current.message)
            placeToast()
            view.layoutIfNeeded()
            toast.transform = Motion.entrance(CGAffineTransform(translationX: 0, y: 20).scaledBy(x: 0.9, y: 0.9))
            SystemAccessibility.post(.announcement, argument: current.message)
        }
        UIView.animate(springDuration: 0.35, bounce: Motion.bounce(0.2)) {
            self.toast.alpha = current == nil ? 0 : 1
            self.toast.transform = .identity
        }
    }
}
