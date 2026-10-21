import UIKit

/// An action revealed by swiping a row.
struct SwipeAction {
    var title: String
    var symbol: String
    var isDestructive = false
    var handler: () -> Void
}

/// Swiping a row reveals glass buttons over it while the row itself stays still. The buttons grow in one by one,
/// following the finger. Releasing past halfway keeps them open; swiping far enough fires the edge-most action.
final class SwipeActionsController: NSObject {
    enum Edge {
        case leading, trailing
    }

    /// The actions for a row and edge, edge-most first. Empty means that edge has none.
    var actions: (IndexPath, Edge) -> [SwipeAction] = { _, _ in [] }

    private weak var collectionView: UICollectionView?
    private let pan = UIPanGestureRecognizer()
    private var overlay: SwipeOverlayView?
    private var indexPath: IndexPath?
    private var isOpen = false
    private var feedback: UIImpactFeedbackGenerator?

    /// How far past the revealed buttons a swipe must travel, as a share of the row's width, to fire the first.
    static let fullSwipeFraction: CGFloat = 0.55

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
        guard let overlay else { return false }
        self.overlay = nil
        indexPath = nil
        isOpen = false
        let hide = { overlay.setProgress(0, fullSwipe: false) }
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
            guard let overlay else { return }
            let start = isOpen ? overlay.revealWidth : 0
            update(distance: start + overlay.towardEdge * dx, overlay: overlay)
        case .ended, .cancelled, .failed:
            guard let overlay else { return }
            let start = isOpen ? overlay.revealWidth : 0
            let distance = start + overlay.towardEdge * dx
            let velocity = overlay.towardEdge * pan.velocity(in: collectionView).x
            finish(distance: distance, velocity: velocity, overlay: overlay, cancelled: pan.state != .ended)
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
        if let indexPath, indexPath == target, let overlay, isOpen,
            (dx < 0) == (overlay.side == .right)
        {
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
        self.overlay = overlay
        indexPath = target
        feedback = UIImpactFeedbackGenerator(style: .medium, view: collectionView)
        feedback?.prepare()
    }

    private func update(distance: CGFloat, overlay: SwipeOverlayView) {
        let fullSwipe = isFullSwipe(distance, overlay: overlay)
        if fullSwipe != overlay.isFullSwipe {
            feedback?.impactOccurred()
            UIView.animate(springDuration: 0.25, bounce: 0.2) {
                overlay.setProgress(distance / overlay.revealWidth, fullSwipe: fullSwipe)
            }
        } else {
            overlay.setProgress(distance / overlay.revealWidth, fullSwipe: fullSwipe)
        }
    }

    private func finish(distance: CGFloat, velocity: CGFloat, overlay: SwipeOverlayView, cancelled: Bool) {
        if !cancelled, isFullSwipe(distance, overlay: overlay), let first = overlay.actions.first {
            close()
            first.handler()
            return
        }
        let opens = !cancelled && (distance + velocity * 0.15 > overlay.revealWidth / 2)
        if opens {
            isOpen = true
            UIView.animate(springDuration: 0.35, bounce: 0.15) { overlay.setProgress(1, fullSwipe: false) }
        } else {
            close()
        }
    }

    private func isFullSwipe(_ distance: CGFloat, overlay: SwipeOverlayView) -> Bool {
        distance > max(overlay.revealWidth + 40, overlay.bounds.width * Self.fullSwipeFraction)
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

/// The glass buttons over one row, laid out from the side the swipe uncovers.
final class SwipeOverlayView: UIView {
    enum Side {
        case left, right
    }

    let actions: [SwipeAction]
    let side: Side
    var onAction: ((SwipeAction) -> Void)?
    private(set) var isFullSwipe = false
    private var buttons: [GlassActionButton] = []
    private var progress: CGFloat = 0

    private static let diameter: CGFloat = 48
    private static let spacing: CGFloat = 10
    private static let inset: CGFloat = 16

    /// +1 when a rightward drag reveals more, −1 when a leftward one does.
    var towardEdge: CGFloat { side == .left ? 1 : -1 }

    /// The swipe distance at which every button is fully shown.
    var revealWidth: CGFloat {
        Self.inset + CGFloat(actions.count) * (Self.diameter + Self.spacing)
    }

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
            addSubview(button)
        }
        setProgress(0, fullSwipe: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Touches between the buttons fall through to the list, so a tap on the row still reaches it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        buttons.contains { !$0.isHidden && $0.frame.insetBy(dx: -4, dy: -4).contains(point) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutButtons()
    }

    /// `progress` 0 hides every button and 1 shows them all; between, each grows in from the edge in turn.
    func setProgress(_ progress: CGFloat, fullSwipe: Bool) {
        self.progress = max(0, progress)
        isFullSwipe = fullSwipe
        layoutButtons()
    }

    private func layoutButtons() {
        let count = CGFloat(buttons.count)
        let y = bounds.midY - Self.diameter / 2
        for (index, button) in buttons.enumerated() {
            let offset = Self.inset + CGFloat(index) * (Self.diameter + Self.spacing)
            let x = side == .right ? bounds.width - offset - Self.diameter : offset
            button.bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
            button.center = CGPoint(x: x + Self.diameter / 2, y: y + Self.diameter / 2)
            // The edge-most button leads; each next one starts once the one before is half grown.
            let share = min(1, max(0, (progress * count - CGFloat(index)) / 1.0))
            let appear = isFullSwipe ? (index == 0 ? 1 : 0) : share
            let scale = isFullSwipe && index == 0 ? 1.25 : 0.5 + 0.5 * appear
            let slide = (1 - appear) * 16 * (side == .right ? 1 : -1)
            button.alpha = appear
            button.transform = CGAffineTransform(translationX: slide, y: 0).scaledBy(x: scale, y: scale)
            button.isHidden = appear == 0
        }
    }
}

/// A round Liquid Glass button showing an action's symbol; destructive ones are tinted red.
final class GlassActionButton: UIControl {
    private let effectView: UIVisualEffectView
    private let imageView = UIImageView()

    init(action: SwipeAction) {
        let glass = UIGlassEffect()
        glass.isInteractive = true
        if action.isDestructive { glass.tintColor = .systemRed }
        effectView = UIVisualEffectView(effect: glass)
        super.init(frame: .zero)
        effectView.cornerConfiguration = .capsule()
        effectView.isUserInteractionEnabled = false
        effectView.frame = bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(effectView)
        imageView.image = UIImage(systemName: action.symbol)
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title3, scale: .medium)
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
