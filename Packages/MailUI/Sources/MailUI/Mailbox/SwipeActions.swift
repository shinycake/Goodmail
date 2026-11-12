import UIKit

/// An action revealed by swiping a row.
struct SwipeAction {
    var title: String
    var symbol: String
    var isDestructive = false
    var handler: () -> Void
}

/// Swiping a row reveals glass buttons over it while the row itself stays still. The buttons slide in from the
/// row's edge, following the finger. Releasing past halfway keeps them open; swiping far enough fires the edge-most
/// action.
final class SwipeActionsController: NSObject {
    enum Edge {
        case leading, trailing
    }

    /// A row whose actions are on screen.
    private struct Row {
        let overlay: SwipeOverlayView
        let indexPath: IndexPath
        let feedback: UIImpactFeedbackGenerator
    }

    /// Where the swipe stands. Dragging a row that is already open starts from its fully revealed buttons.
    private enum State {
        /// No row shows its actions.
        case idle
        /// A drag is uncovering a row's actions from closed.
        case revealing(Row)
        /// A row's actions settled open; a drag on it continues from there.
        case open(Row)

        var row: Row? {
            switch self {
            case .idle: nil
            case .revealing(let row), .open(let row): row
            }
        }

        /// How far the buttons are revealed once the finger has moved `dx` from where the drag began.
        func distance(dx: CGFloat) -> CGFloat? {
            switch self {
            case .idle: nil
            case .revealing(let row): row.overlay.towardEdge * dx
            case .open(let row): row.overlay.layout.revealWidth + row.overlay.towardEdge * dx
            }
        }
    }

    /// The actions for a row and edge, edge-most first. Empty means that edge has none.
    var actions: (IndexPath, Edge) -> [SwipeAction] = { _, _ in [] }

    private weak var collectionView: UICollectionView?
    private let pan = UIPanGestureRecognizer()
    private var state = State.idle

    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        super.init()
        pan.addTarget(self, action: #selector(handlePan))
        pan.delegate = self
        collectionView.addGestureRecognizer(pan)
    }

    /// Hides any open actions, as when the list scrolls or another row is tapped. Returns whether any were open.
    @discardableResult
    func close(animated: Bool = true) -> Bool {
        guard let overlay = state.row?.overlay else { return false }
        state = .idle
        let hide = { overlay.reveal = .tracking(0) }
        if animated {
            UIView.animate(springDuration: 0.3, bounce: 0, animations: hide) { _ in overlay.removeFromSuperview() }
        } else {
            overlay.removeFromSuperview()
        }
        return true
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let collectionView else { return }
        let dx = pan.translation(in: collectionView).x
        switch pan.state {
        case .began:
            // The translation is still zero when the pan begins; the velocity tells which way it's heading.
            begin(at: pan.location(in: collectionView), dx: pan.velocity(in: collectionView).x, in: collectionView)
        case .changed:
            guard let row = state.row, let distance = state.distance(dx: dx) else { return }
            update(distance: distance, row: row)
        case .ended, .cancelled, .failed:
            guard let row = state.row, let distance = state.distance(dx: dx) else { return }
            let velocity = row.overlay.towardEdge * pan.velocity(in: collectionView).x
            finish(distance: distance, velocity: velocity, row: row, cancelled: pan.state != .ended)
        default:
            break
        }
    }

    private func begin(at location: CGPoint, dx: CGFloat, in collectionView: UICollectionView) {
        // Stop the list from scrolling under the finger once the swipe has started.
        collectionView.panGestureRecognizer.isEnabled = false
        collectionView.panGestureRecognizer.isEnabled = true
        guard let target = collectionView.indexPathForItem(at: location),
            let cell = collectionView.cellForItem(at: target)
        else { return }
        if case .open(let row) = state, row.indexPath == target, (dx < 0) == (row.overlay.side == .right) {
            return  // Dragging the open actions further or back.
        }
        close(animated: false)
        // Moving left uncovers the right side, as if the row slid; which edge that is depends on the layout direction.
        let side: SwipeOverlayView.Side = dx < 0 ? .right : .left
        let isRightToLeft = collectionView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let edge: Edge = (side == .right) != isRightToLeft ? .trailing : .leading
        let actions = actions(target, edge)
        guard !actions.isEmpty else { return }
        let overlay = SwipeOverlayView(actions: actions, side: side)
        overlay.frame = cell.frame
        overlay.layer.zPosition = 10
        overlay.onAction = { [weak self] action in
            self?.close()
            action.handler()
        }
        collectionView.addSubview(overlay)
        let feedback = UIImpactFeedbackGenerator(style: .medium, view: collectionView)
        feedback.prepare()
        state = .revealing(Row(overlay: overlay, indexPath: target, feedback: feedback))
    }

    private func update(distance: CGFloat, row: Row) {
        let overlay = row.overlay
        let reveal = overlay.layout.reveal(at: distance)
        if reveal.isFullSwipe != overlay.reveal.isFullSwipe {
            row.feedback.impactOccurred()
            UIView.animate(springDuration: 0.3, bounce: 0.2) { overlay.reveal = reveal }
        } else {
            overlay.reveal = reveal
        }
    }

    private func finish(distance: CGFloat, velocity: CGFloat, row: Row, cancelled: Bool) {
        let overlay = row.overlay
        let layout = overlay.layout
        if !cancelled, layout.reveal(at: distance).isFullSwipe, let first = overlay.actions.first {
            close()
            first.handler()
            return
        }
        if !cancelled, distance + velocity * 0.15 > layout.revealWidth / 2 {
            state = .open(row)
            UIView.animate(springDuration: 0.35, bounce: 0.15) { overlay.reveal = .tracking(layout.revealWidth) }
        } else {
            close()
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
enum SwipeReveal: Equatable {
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
struct SwipeLayout {
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
    enum Side {
        case left, right
    }

    let actions: [SwipeAction]
    let side: Side
    var onAction: ((SwipeAction) -> Void)?
    var reveal: SwipeReveal = .tracking(0) {
        didSet { layoutButtons() }
    }
    private var buttons: [GlassActionButton] = []

    /// +1 when a rightward drag reveals more, −1 when a leftward one does.
    var towardEdge: CGFloat { side == .left ? 1 : -1 }

    var layout: SwipeLayout { SwipeLayout(count: actions.count, rowWidth: bounds.width) }

    init(actions: [SwipeAction], side: Side) {
        self.actions = actions
        self.side = side
        super.init(frame: .zero)
        for action in actions {
            let button = GlassActionButton(action: action)
            button.addAction(
                // A plain `UIControl` sends touch events, not `.primaryActionTriggered`.
                UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
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

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(springDuration: 0.2, bounce: 0.3) {
                self.effectView.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }
}
