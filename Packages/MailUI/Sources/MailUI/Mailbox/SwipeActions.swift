import MailCore
import UIKit

/// An action revealed by swiping a row.
struct SwipeAction {
    var title: String
    var symbol: String
    var isDestructive = false
    /// The box the row is seen going into when the action puts it away; `nil` when the buttons just close.
    var stow: StowKind?
    /// Runs the action. For one that stows, `stowing` carries the opened box on the action's button, and the
    /// buttons stay up until the handler calls its `done`.
    var handler: (_ stowing: Stowing?) -> Void

    /// A stow in progress from a swipe button.
    struct Stowing {
        let box: StowBoxView
        /// Takes the buttons away, once the row has gone into the box.
        let done: () -> Void
    }
}

/// Swiping a row reveals glass buttons over it while the row itself stays still. The buttons slide in from the
/// row's edge, following the finger. Releasing past halfway keeps them open; swiping far enough fires the edge-most
/// action. The buttons ride on the row's cell, so they stay on their row when mail arrives above it.
final class SwipeActionsController: NSObject {
    enum Edge {
        case leading, trailing
    }

    /// A row whose actions are on screen.
    struct Row: Identifiable {
        let id: ThreadSummary.ID
        let overlay: SwipeOverlayView
        let feedback: UIImpactFeedbackGenerator
    }

    /// The actions for a row and edge, edge-most first. Empty means that edge has none.
    var actions: (ThreadSummary.ID, Edge) -> [SwipeAction] = { _, _ in [] }

    private weak var collectionView: UICollectionView?
    private let rowID: (IndexPath) -> ThreadSummary.ID?
    private let indexPath: (ThreadSummary.ID) -> IndexPath?
    private let pan = UIPanGestureRecognizer()
    private var state = SwipeState<Row>.idle

    /// `rowID` and `indexPath` translate between the list's positions and its rows' stable identities.
    init(
        collectionView: UICollectionView, rowID: @escaping (IndexPath) -> ThreadSummary.ID?,
        indexPath: @escaping (ThreadSummary.ID) -> IndexPath?
    ) {
        self.collectionView = collectionView
        self.rowID = rowID
        self.indexPath = indexPath
        super.init()
        pan.addTarget(self, action: #selector(handlePan))
        pan.delegate = self
        collectionView.addGestureRecognizer(pan)
    }

    /// Hides any open actions, as when the list scrolls or another row is tapped. Returns whether any were open.
    @discardableResult
    func close(animated: Bool = true) -> Bool {
        guard let row = state.close() else { return false }
        hide(row, animated: animated)
        return true
    }

    /// Keeps the open buttons on their row after the list changed: on the row's cell if the list gave it a new one,
    /// or gone with the row when it left the list or the screen.
    func rowsDidChange() {
        guard let row = state.row, let collectionView else { return }
        guard let indexPath = indexPath(row.id), let cell = collectionView.cellForItem(at: indexPath) else {
            close(animated: false)
            return
        }
        if row.overlay.superview !== cell { attach(row.overlay, to: cell) }
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let collectionView else { return }
        let dx = pan.translation(in: collectionView).x
        switch pan.state {
        case .began:
            // The translation is still zero when the pan begins; the velocity tells which way it's heading.
            begin(at: pan.location(in: collectionView), heading: pan.velocity(in: collectionView).x, in: collectionView)
        case .changed:
            guard let row = state.row, let distance = state.distance(afterMoving: dx) else { return }
            update(distance: distance, row: row)
        case .ended, .cancelled, .failed:
            guard let layout = state.row?.overlay.layout else { return }
            let velocity = pan.velocity(in: collectionView).x
            switch state.end(afterMoving: dx, velocity: velocity, layout: layout, cancelled: pan.state != .ended) {
            case .fired(let row):
                guard let action = row.overlay.actions.first, let button = row.overlay.buttons.first else { break }
                fire(action, from: button, on: row)
            case .opened(let row, let width):
                UIView.animate(springDuration: 0.35, bounce: Motion.bounce(0.15)) {
                    row.overlay.reveal = .tracking(width)
                }
            case .closed(let row):
                hide(row, animated: true)
            case nil:
                break
            }
        default:
            break
        }
    }

    private func begin(at location: CGPoint, heading dx: CGFloat, in collectionView: UICollectionView) {
        // Stop the list from scrolling under the finger once the swipe has started.
        collectionView.panGestureRecognizer.isEnabled = false
        collectionView.panGestureRecognizer.isEnabled = true
        guard let target = collectionView.indexPathForItem(at: location), let id = rowID(target),
            let cell = collectionView.cellForItem(at: target)
        else { return }
        let replaced = state.begin(on: id, heading: dx) { side in
            makeRow(id, side: side, on: cell, in: collectionView)
        }
        if let replaced { hide(replaced, animated: false) }
    }

    private func makeRow(
        _ id: ThreadSummary.ID, side: SwipeSide, on cell: UICollectionViewCell, in collectionView: UICollectionView
    ) -> Row? {
        let isRightToLeft = collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let edge: Edge = (side == .right) != isRightToLeft ? .trailing : .leading
        let actions = actions(id, edge)
        guard !actions.isEmpty else { return nil }
        let overlay = SwipeOverlayView(actions: actions, side: side)
        overlay.onAction = { [weak self] action, button in
            guard let self, let row = state.close() else { return }
            fire(action, from: button, on: row)
        }
        attach(overlay, to: cell)
        let feedback = UIImpactFeedbackGenerator(style: .medium, view: collectionView)
        feedback.prepare()
        return Row(id: id, overlay: overlay, feedback: feedback)
    }

    /// Puts the buttons on `cell`, above its content, so they move with it.
    private func attach(_ overlay: SwipeOverlayView, to cell: UICollectionViewCell) {
        overlay.frame = cell.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.layer.zPosition = 10
        cell.addSubview(overlay)
    }

    /// Runs `action`. One that stows keeps the buttons up and turns its own into the box the row goes into; any
    /// other closes them first.
    private func fire(_ action: SwipeAction, from button: GlassActionButton, on row: Row) {
        guard let kind = action.stow, !UIAccessibility.isReduceMotionEnabled else {
            hide(row, animated: true)
            return action.handler(nil)
        }
        let overlay = row.overlay
        overlay.isUserInteractionEnabled = false
        action.handler(
            SwipeAction.Stowing(box: button.showBox(kind)) {
                UIView.animate(withDuration: 0.2) {
                    overlay.alpha = 0
                } completion: { _ in
                    overlay.removeFromSuperview()
                }
            })
    }

    private func hide(_ row: Row, animated: Bool) {
        let overlay = row.overlay
        guard animated else { return overlay.removeFromSuperview() }
        UIView.animate(springDuration: 0.3, bounce: 0) {
            overlay.reveal = .tracking(0)
        } completion: { _ in
            overlay.removeFromSuperview()
        }
    }

    private func update(distance: CGFloat, row: Row) {
        let overlay = row.overlay
        let reveal = overlay.layout.reveal(at: distance)
        if reveal.isFullSwipe != overlay.reveal.isFullSwipe {
            row.feedback.impactOccurred()
            UIView.animate(springDuration: 0.3, bounce: Motion.bounce(0.2)) { overlay.reveal = reveal }
        } else {
            overlay.reveal = reveal
        }
    }
}

extension SwipeActionsController: UIGestureRecognizerDelegate {
    /// Only clearly horizontal drags swipe; anything steeper scrolls the list.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, let collectionView, !collectionView.isEditing else { return false }
        let velocity = pan.velocity(in: collectionView)
        return abs(velocity.x) > abs(velocity.y) * 1.5
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        other === collectionView?.panGestureRecognizer
    }
}

/// How far a swipe has gone: either revealing the buttons, or past the point where letting go fires the first.
nonisolated enum SwipeReveal: Equatable {
    /// The finger has moved this far toward the edge; the buttons follow it.
    case tracking(CGFloat)
    /// The finger has moved this far, enough to fire the edge-most action on release.
    case fullSwipe(CGFloat)

    var isFullSwipe: Bool {
        if case .fullSwipe = self { true } else { false }
    }
}

/// Where each swipe button sits, measured inward from the row's edge, for a given reveal. Pure geometry, so the
/// slide can be checked without a screen.
nonisolated struct SwipeLayout {
    var count: Int
    var rowWidth: CGFloat

    static let diameter: CGFloat = 60
    static let spacing: CGFloat = 12
    static let inset: CGFloat = 16
    /// How far past the revealed buttons a swipe must travel, as a share of the row's width, to fire the first.
    static let fullSwipeFraction: CGFloat = 0.55

    /// The swipe distance at which every button is fully shown.
    var revealWidth: CGFloat {
        Self.inset + CGFloat(count) * (Self.diameter + Self.spacing)
    }

    func reveal(at distance: CGFloat) -> SwipeReveal {
        distance > max(revealWidth + 40, rowWidth * Self.fullSwipeFraction) ? .fullSwipe(distance) : .tracking(distance)
    }

    /// Where button `index` rests once fully shown, from the edge to its outer side.
    func restingOffset(_ index: Int) -> CGFloat {
        Self.inset + CGFloat(index) * (Self.diameter + Self.spacing)
    }

    /// Each button's distance from the edge to its outer side, and whether it shows.
    ///
    /// While tracking, every button starts just past the edge and slides to its resting place as the finger
    /// uncovers the row, the inner ones travelling further, so the stack fans out from the edge. On a full swipe
    /// the edge-most button rides along at the finger and the rest fall away.
    func placements(for reveal: SwipeReveal) -> [(offset: CGFloat, isVisible: Bool)] {
        (0..<count).map { index in
            let rest = restingOffset(index)
            switch reveal {
            case .tracking(let distance):
                let progress = min(1, max(0, distance / revealWidth))
                let offset = -Self.diameter + (rest + Self.diameter) * progress
                return (offset, offset > -Self.diameter)
            case .fullSwipe(let distance):
                guard index == 0 else { return (rest, false) }
                let atFinger = distance - Self.diameter - Self.spacing
                return (min(max(rest, atFinger), rowWidth - Self.diameter - Self.inset), true)
            }
        }
    }
}

/// The glass buttons over one row, laid out from the side the swipe uncovers.
final class SwipeOverlayView: UIView {
    let actions: [SwipeAction]
    let side: SwipeSide
    var onAction: ((SwipeAction, GlassActionButton) -> Void)?
    var reveal: SwipeReveal = .tracking(0) {
        didSet { layoutButtons() }
    }
    /// One for each action, in the same order.
    private(set) var buttons: [GlassActionButton] = []

    var layout: SwipeLayout { SwipeLayout(count: actions.count, rowWidth: bounds.width) }

    init(actions: [SwipeAction], side: SwipeSide) {
        self.actions = actions
        self.side = side
        super.init(frame: .zero)
        for action in actions {
            let button = GlassActionButton(action: action)
            button.addAction(
                // A plain `UIControl` sends touch events, not `.primaryActionTriggered`.
                UIAction { [weak self, unowned button] _ in self?.onAction?(action, button) }, for: .touchUpInside)
            buttons.append(button)
            // The edge-most button stays on top, so the inner ones fan out from under it.
            insertSubview(button, at: 0)
        }
        layoutButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Touches between the buttons fall through to the list, so a tap on the row still reaches it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        buttons.contains { $0.alpha > 0 && $0.frame.insetBy(dx: -4, dy: -4).contains(point) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutButtons()
    }

    private func layoutButtons() {
        let diameter = SwipeLayout.diameter
        for (button, placement) in zip(buttons, layout.placements(for: reveal)) {
            let x = side == .right ? bounds.width - placement.offset - diameter : placement.offset
            button.frame = CGRect(x: x, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
            // Fading rather than hiding keeps the slide smooth inside the spring animations.
            button.alpha = placement.isVisible ? 1 : 0
        }
    }
}

/// A round button of clear Liquid Glass showing an action's symbol, so the row shows through it; destructive ones
/// are tinted red.
final class GlassActionButton: UIControl {
    private let effectView: UIVisualEffectView
    private let imageView = UIImageView()

    init(action: SwipeAction) {
        let glass = UIGlassEffect(style: .clear)
        glass.isInteractive = true
        if action.isDestructive { glass.tintColor = .systemRed.withAlphaComponent(0.8) }
        effectView = UIVisualEffectView(effect: glass)
        super.init(frame: .zero)
        effectView.cornerConfiguration = .capsule()
        effectView.isUserInteractionEnabled = false
        effectView.frame = bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(effectView)
        imageView.image = UIImage(systemName: action.symbol)
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2, scale: .large)
        imageView.tintColor = action.isDestructive ? .white : .label
        imageView.contentMode = .center
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        effectView.contentView.addSubview(imageView)
        isAccessibilityElement = true
        accessibilityLabel = action.title
        accessibilityTraits = .button
    }

    /// Swaps the symbol for a drawn `kind` box whose lid can open, in the symbol's color.
    func showBox(_ kind: StowKind) -> StowBoxView {
        let box = StowBoxView(kind: kind, color: imageView.tintColor)
        box.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        box.center = CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        imageView.image = nil
        imageView.addSubview(box)
        box.layoutIfNeeded()
        return box
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(springDuration: 0.2, bounce: Motion.bounce(0.3)) {
                self.effectView.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
}
