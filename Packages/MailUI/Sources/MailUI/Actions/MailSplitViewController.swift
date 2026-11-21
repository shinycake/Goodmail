public import UIKit

/// A window's mail screens: mailboxes, a mailbox's list and a thread side by side when the window is wide, one
/// stack when it is narrow. The undo toast floats over them, above the toolbars, over the thread's column when they
/// are side by side, or in the middle of a toolbar that leaves it room (`UndoToastLane`), and off iPhone Duo's fold (`FoldLane`). Shaking to undo is
/// the window's (`ShakeToUndoWindow`), so that no screen holds first responder and raises the keyboard with a menu.
public final class MailSplitViewController: UISplitViewController {
    private let actions: MailActions
    private let toast = UndoToastView()
    private var shownToast: MailActions.Toast.ID?
    private var toastBottom: NSLayoutConstraint!
    /// Centers the toast in its lane, measured from the physical left as the lane is, and keeps it within the
    /// lane's width.
    private var toastCenter: NSLayoutConstraint!
    private var toastWidth: NSLayoutConstraint!
    /// The column arrangement last asked for, so a width that keeps it doesn't undo the sidebar button.
    private var preferredColumns: DisplayMode?
    /// Where an empty Inbox's paper planes fly in this window, and the view drawing them over the columns.
    let inboxZeroSky = InboxZeroSky()
    private(set) lazy var inboxZeroSkyView = makeInboxZeroSkyView()
    /// Names each column's toolbar buttons and their keys on a desktop window.
    private let toolTips = BarToolTips()
    /// Next and Previous Conversation, from the window's navigation (`WindowNavigator`).
    public var steps: ConversationSteps?

    public init(actions: MailActions) {
        self.actions = actions
        super.init(style: .tripleColumn)
        preferredSplitBehavior = .tile
        minimumSecondaryColumnWidth = MailColumns.minimumThreadWidth
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(inboxZeroSkyView)
        let haptics = HapticPlayer(view: view)
        actions.feedback = { haptics.play($0) }
        toast.alpha = 0
        toast.onUndo = { [weak self] in self?.actions.undoLast() }
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        toastBottom = toast.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        toastCenter = toast.centerXAnchor.constraint(equalTo: view.leftAnchor)
        toastWidth = toast.widthAnchor.constraint(lessThanOrEqualToConstant: 0)
        NSLayoutConstraint.activate([toastBottom, toastCenter, toastWidth])
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let columns = MailColumns.displayMode(forWidth: view.bounds.width)
        guard columns != preferredColumns else { return }
        preferredColumns = columns
        preferredDisplayMode = columns
    }

    /// Shows the list after the reader picked a mailbox, closing the sidebar when it took the list's place.
    public func showList() {
        show(.supplementary)
        if preferredColumns == .oneBesideSecondary { hide(.primary) }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeInboxZeroSky()
        placeToast()
        if traitCollection.interactionStyle == .desktop {
            for column in [Column.primary, .supplementary, .secondary] {
                (viewController(for: column) as? UINavigationController).map { toolTips.install(on: $0.navigationBar) }
            }
        }
    }

    private func placeToast() {
        view.bringSubviewToFront(toast)
        let lane = toastLane
        let center = lane.midX - view.bounds.minX
        if toastCenter.constant != center { toastCenter.constant = center }
        let width = max(lane.width - 2 * Self.toastMargin, 0)
        if toastWidth.constant != width { toastWidth.constant = width }
        let size = toast.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let placement = UndoToastPlacement.choose(
            ends: toolbarEnds(), midX: lane.midX, toastSize: size, aboveInset: aboveToolbars() + Self.toastGap)
        let constant = placement.bottomConstant(in: view.bounds, toastHeight: size.height)
        if toastBottom.constant != constant { toastBottom.constant = constant }
        tellFloors(toastHeight: actions.toast == nil ? 0 : size.height + Self.toastGap)
    }

    /// Where the toast sits across the window: the whole of it in one stack, and the thread's column side by side,
    /// over its toolbar, rather than across the line between the columns and over the list's rows. The column's own
    /// safe area leaves out the sidebar when it floats over the column's edge.
    private var toastLane: CGRect {
        let lane = view.foldLane
        guard let column = toastScreens.first?.view, !isCollapsed else { return lane }
        let insets = column.safeAreaInsets
        let frame = column.convert(
            column.bounds.inset(by: UIEdgeInsets(top: 0, left: insets.left, bottom: 0, right: insets.right)), to: view)
        let inColumn = lane.intersection(frame)
        return inColumn.width < Self.narrowestToastLane ? lane : inColumn
    }

    /// The least width the toast keeps to a column for; narrower, it takes the window's.
    private static let narrowestToastLane: CGFloat = 280

    /// The screens the toast sits above: the one stack's top, or the thread's column side by side.
    private var toastScreens: [UIViewController] {
        isCollapsed ? shownScreens : shownScreens(in: [.secondary])
    }

    /// The room between the toast and what it sits above.
    private static let toastGap: CGFloat = 12

    /// Tells screens with a bar of their own how much the toast covers above it.
    private func tellFloors(toastHeight: CGFloat) {
        for case let floor as any UndoToastFloor in shownScreens { floor.toastCovers(toastHeight) }
    }

    /// The least room the toast leaves to either side of its lane.
    private static let toastMargin: CGFloat = 16

    /// How far the shown screens' content ends above the bottom: a screen's safe area ends above its toolbar when
    /// there is one, else above the home indicator, and a bar of its own, such as the chat's field, may end higher.
    private func aboveToolbars() -> CGFloat {
        let insets = toastScreens.map { screen in
            guard let floor = (screen as? any UndoToastFloor)?.toastFloor, floor.window != nil else {
                return screen.view.safeAreaInsets.bottom
            }
            return max(screen.view.safeAreaInsets.bottom, view.bounds.maxY - floor.convert(floor.bounds, to: view).minY)
        }
        return insets.max() ?? view.safeAreaInsets.bottom
    }

    /// The frames of the toolbar's end buttons, in this view's coordinates, when one screen fills the window and
    /// its toolbar's middle is open for the toast. Side by side, the toast stays centered on the window, not on one
    /// column's toolbar. The buttons' own frames, as the toolbar view's is the whole window on iOS 27. A button that
    /// reports an empty frame is left out: the toast, centered, keeps the same room from both ends, so the buttons
    /// that do report one are enough. A toolbar in a bar down the side, as on iPhone Duo's outer display, has no
    /// middle for the toast.
    private func toolbarEnds() -> [CGRect] {
        guard isCollapsed, traitCollection.verticalBarEdge == .unspecified,
            let lane = shownScreens.first as? any UndoToastLane,
            lane.navigationController?.isToolbarHidden == false
        else { return [] }
        return lane.toolbarEnds.compactMap { $0.frame(in: view) }.filter { !$0.isEmpty }
    }

    /// The screen on top in each shown column.
    private var shownScreens: [UIViewController] {
        shownScreens(in: isCollapsed ? [.compact] : [.primary, .supplementary, .secondary])
    }

    /// The screen on top in each of `columns` that is on show.
    private func shownScreens(in columns: [Column]) -> [UIViewController] {
        columns.compactMap { column in
            let shown = viewController(for: column)
            let top = (shown as? UINavigationController)?.topViewController ?? shown
            guard let top, top.view.window != nil else { return nil }
            return top
        }
    }

    /// VoiceOver's two-finger double tap undoes while the toast shows, wherever VoiceOver is, as the play/pause of
    /// the Magic Tap does in Phone and Music.
    public override func accessibilityPerformMagicTap() -> Bool {
        guard actions.toast?.offersUndo == true else { return false }
        actions.undoLast()
        return true
    }

    /// Called by UIKit whenever the observed toast changes.
    public override func updateProperties() {
        super.updateProperties()
        let current = actions.toast
        guard current?.id != shownToast else { return }
        shownToast = current?.id
        if current == nil { tellFloors(toastHeight: 0) }
        if let current {
            toast.show(current.message, offeringUndo: current.offersUndo)
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
