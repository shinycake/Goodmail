import MailCore
import UIKit

/// An action revealed by swiping a row.
struct SwipeAction {
    var title: String
    var symbol: String
    var tint: SwipeTint
    /// The action's own color, which a clear button fills with on a full swipe.
    var color: UIColor
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
    /// A row whose actions are on screen.
    struct Row: Identifiable {
        let id: ThreadSummary.ID
        let overlay: SwipeOverlayView
        let feedback: UIImpactFeedbackGenerator
    }

    /// The actions for a row and side, edge-most first. Empty means that side has none.
    var actions: (ThreadSummary.ID, SwipeSide) -> [SwipeAction] = { _, _ in [] }
    /// Opens the swipe settings, as when a button is touched and held.
    var openSettings: () -> Void = {}

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

    /// Keeps the buttons on their row after the list changed: gone with the row when it left the list, and moved to
    /// the row's cell if the list gave it a new one. While the list is still updating it may not have the row's cell
    /// yet; the buttons then stay on the cell they ride, and `cellDidEndDisplaying(_:)` takes them off if it goes.
    func rowsDidChange() {
        guard let row = state.row, let collectionView else { return }
        guard let indexPath = indexPath(row.id) else {
            close(animated: false)
            return
        }
        if let cell = collectionView.cellForItem(at: indexPath), row.overlay.superview !== cell {
            attach(row.overlay, to: cell)
        }
    }

    /// A cell left the screen; buttons riding on it would otherwise show on whichever row reuses it.
    func cellDidEndDisplaying(_ cell: UICollectionViewCell) {
        if state.row?.overlay.superview === cell { close(animated: false) }
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let collectionView else { return }
        // Directions are read in the window's coordinates: a right-to-left list runs its x axis mirrored, which would
        // turn a swipe left into a swipe right. Swipes go by the screen, the same in every language.
        let dx = pan.translation(in: nil).x
        switch pan.state {
        case .began:
            // The translation is still zero when the pan begins; the velocity tells which way it's heading.
            begin(at: pan.location(in: collectionView), heading: pan.velocity(in: nil).x, in: collectionView)
        case .changed:
            guard let row = state.row, let distance = state.distance(afterMoving: dx) else { return }
            update(distance: distance, row: row)
        case .ended, .cancelled, .failed:
            guard let layout = state.row?.overlay.layout else { return }
            let velocity = pan.velocity(in: nil).x
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
        let actions = actions(id, side)
        guard !actions.isEmpty else { return nil }
        let overlay = SwipeOverlayView(actions: actions, side: side)
        overlay.onAction = { [weak self] action, button in
            guard let self, let row = state.close() else { return }
            fire(action, from: button, on: row)
        }
        overlay.onSettings = { [weak self] in
            guard let self else { return }
            close()
            openSettings()
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
        guard let kind = action.stow, Motion.playsRemovals else {
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

/// Where a swipe button sits, measured inward from the row's edge to its outer side, and its size.
nonisolated struct SwipePlacement: Equatable {
    var offset: CGFloat
    var width: CGFloat
    var height: CGFloat
    var isVisible: Bool
}

/// Where each swipe button sits for a given reveal. Pure geometry, so the slide can be checked without a screen.
nonisolated struct SwipeLayout {
    var count: Int
    var rowWidth: CGFloat
    var rowHeight: CGFloat
    /// The size the buttons would like, before the row's room caps it: `baseDiameter` scaled for the text size.
    var preferredDiameter = Self.baseDiameter

    /// The buttons' size at the default text size.
    static let baseDiameter: CGFloat = 72
    /// The buttons never get smaller than this, however little room the row has.
    static let minimumDiameter: CGFloat = 60
    /// Nor larger than this, however large the text.
    static let maximumDiameter: CGFloat = 96
    /// The share of the row's width the revealed buttons may take, leaving room to swipe on past them.
    static let maximumRevealFraction: CGFloat = 0.8
    /// The least gap a button leaves above and below it inside its row.
    static let rowClearance: CGFloat = 6
    static let spacing: CGFloat = 12
    static let inset: CGFloat = 16
    /// The gap a full swipe's grown button leaves above and below it.
    static let verticalInset: CGFloat = 8
    /// How far past the revealed buttons a swipe must travel, as a share of the row's width, to fire the first.
    static let fullSwipeFraction: CGFloat = 0.55

    /// The buttons' size: as large as preferred, as long as they fit inside the row's height and leave room to swipe
    /// past them.
    var diameter: CGFloat {
        let widthRoom = (rowWidth * Self.maximumRevealFraction - Self.inset) / CGFloat(max(1, count)) - Self.spacing
        let heightRoom = rowHeight - 2 * Self.rowClearance
        return max(Self.minimumDiameter, min(preferredDiameter, Self.maximumDiameter, widthRoom, heightRoom))
    }

    /// The swipe distance at which every button is fully shown.
    var revealWidth: CGFloat {
        Self.inset + CGFloat(count) * (diameter + Self.spacing)
    }

    func reveal(at distance: CGFloat) -> SwipeReveal {
        distance > max(revealWidth + 40, rowWidth * Self.fullSwipeFraction) ? .fullSwipe(distance) : .tracking(distance)
    }

    /// Where button `index` rests once fully shown, from the edge to its outer side.
    func restingOffset(_ index: Int) -> CGFloat {
        Self.inset + CGFloat(index) * (diameter + Self.spacing)
    }

    /// How far a button placed at `placement` takes touches beyond its glass: up and down to the row's own edges,
    /// and side to side halfway to its neighbors, so the buttons share the row between them and a tap that misses
    /// the glass still lands on the nearest one.
    func touchOutset(for placement: SwipePlacement) -> CGSize {
        CGSize(width: Self.spacing / 2, height: max(0, (rowHeight - placement.height) / 2))
    }

    /// Each button's place and size, and whether it shows.
    ///
    /// While tracking, every button starts just past the edge and slides to its resting place as the finger
    /// uncovers the row, the inner ones travelling further, so the stack fans out from the edge. On a full swipe
    /// the edge-most button grows into a capsule as tall as the row allows, stretching from the edge to the finger
    /// until it covers the row, and the rest fall away.
    func placements(for reveal: SwipeReveal) -> [SwipePlacement] {
        let diameter = diameter
        return (0..<count).map { index in
            let rest = restingOffset(index)
            switch reveal {
            case .tracking(let distance):
                let progress = min(1, max(0, distance / revealWidth))
                let offset = -diameter + (rest + diameter) * progress
                return SwipePlacement(
                    offset: offset, width: diameter, height: diameter, isVisible: offset > -diameter)
            case .fullSwipe(let distance):
                guard index == 0 else {
                    return SwipePlacement(offset: rest, width: diameter, height: diameter, isVisible: false)
                }
                let width = min(max(diameter, distance - Self.inset - Self.spacing), rowWidth - 2 * Self.inset)
                let height = max(diameter, rowHeight - 2 * Self.verticalInset)
                return SwipePlacement(offset: Self.inset, width: width, height: height, isVisible: true)
            }
        }
    }
}

/// The glass buttons over one row, laid out from the side the swipe uncovers.
final class SwipeOverlayView: UIView {
    let actions: [SwipeAction]
    let side: SwipeSide
    var onAction: ((SwipeAction, GlassActionButton) -> Void)?
    /// Asks for the swipe settings, from a button touched and held.
    var onSettings: (() -> Void)?
    var reveal: SwipeReveal = .tracking(0) {
        didSet { layoutButtons() }
    }
    /// One for each action, in the same order.
    private(set) var buttons: [GlassActionButton] = []

    /// Laid out inside the row's safe area side to side, so no button sits under the bar of controls down the side of
    /// iPhone Duo, or under a landscape iPhone's camera.
    var layout: SwipeLayout {
        SwipeLayout(
            count: actions.count, rowWidth: bounds.width - safeAreaInsets.left - safeAreaInsets.right,
            rowHeight: bounds.height,
            preferredDiameter: UIFontMetrics(forTextStyle: .body).scaledValue(
                for: SwipeLayout.baseDiameter, compatibleWith: traitCollection))
    }

    init(actions: [SwipeAction], side: SwipeSide) {
        self.actions = actions
        self.side = side
        super.init(frame: .zero)
        // Past this, larger text would only crowd the symbols out of buttons that stopped growing.
        maximumContentSizeCategory = .accessibilityMedium
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (overlay: Self, _) in
            overlay.setNeedsLayout()
        }
        for action in actions {
            let button = GlassActionButton(action: action)
            button.addAction(
                // A plain `UIControl` sends touch events, not `.primaryActionTriggered`.
                UIAction { [weak self, unowned button] _ in self?.onAction?(action, button) }, for: .touchUpInside)
            button.onLongPress = { [weak self] in self?.onSettings?() }
            buttons.append(button)
            // The edge-most button stays on top, so the inner ones fan out from under it.
            insertSubview(button, at: 0)
        }
        layoutButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Touches beside the buttons' share of the row fall through to the list, so a tap on the row still reaches it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        buttons.contains { $0.alpha > 0 && $0.point(inside: convert(point, to: $0), with: event) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutButtons()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    private func layoutButtons() {
        let layout = layout
        for (button, placement) in zip(buttons, layout.placements(for: reveal)) {
            let x =
                side == .right
                ? bounds.width - safeAreaInsets.right - placement.offset - placement.width
                : safeAreaInsets.left + placement.offset
            button.frame = CGRect(
                x: x, y: bounds.midY - placement.height / 2, width: placement.width, height: placement.height)
            // Fading rather than hiding keeps the slide smooth inside the spring animations.
            button.alpha = placement.isVisible ? 1 : 0
            button.touchOutset = layout.touchOutset(for: placement)
            button.isCommitted = reveal.isFullSwipe && placement.isVisible
            // Lays the symbol and title out now, inside any animation, so they move with the button's shape.
            button.layoutIfNeeded()
        }
    }
}

/// A round button of Liquid Glass showing an action's symbol: clear, so the row shows through it, or filled with
/// the action's tint. Stretched wide, as on a full swipe, it names the action beside the symbol.
final class GlassActionButton: UIControl {
    private let tint: SwipeTint
    private let color: UIColor
    private let effectView = UIVisualEffectView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    /// The drawn box standing in for the symbol while rows go into it; `nil` while the symbol shows.
    private var box: StowBoxView?
    /// How wide the button must be to name its action.
    private static let titledWidth: CGFloat = 160

    /// Whether letting go fires this action, as on a full swipe: the glass fills with the action's color, so it
    /// reads as solid over the row it covers.
    var isCommitted = false {
        didSet { if isCommitted != oldValue { applyGlass() } }
    }

    /// Touching and holding the button asks for this, as to open the swipe settings.
    var onLongPress: (() -> Void)?

    /// How far beyond its glass the button still takes a touch, on each side and above and below.
    var touchOutset = CGSize.zero

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -touchOutset.width, dy: -touchOutset.height).contains(point)
    }

    init(action: SwipeAction) {
        tint = action.tint
        color = action.color
        super.init(frame: .zero)
        effectView.cornerConfiguration = .capsule()
        effectView.isUserInteractionEnabled = false
        effectView.frame = bounds
        effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(effectView)
        imageView.image = UIImage(systemName: action.symbol)
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2, scale: .large)
        imageView.contentMode = .center
        effectView.contentView.addSubview(imageView)
        titleLabel.text = action.title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.alpha = 0
        effectView.contentView.addSubview(titleLabel)
        isAccessibilityElement = true
        accessibilityLabel = action.title
        accessibilityTraits = .button
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: SwipeSettingsView.title) { [weak self] _ in
                self?.onLongPress?()
                return true
            }
        ]
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed)))
        applyGlass()
    }

    @objc private func longPressed(_ press: UILongPressGestureRecognizer) {
        guard press.state == .began else { return }
        // The touch that began the hold must not also fire the action when it lifts.
        cancelTracking(with: nil)
        onLongPress?()
    }

    /// A picked color, as a tint shaded for light or dark mode under a symbol in its hue. Clear glass stays clear,
    /// with the label color for its symbol, until a full swipe fills it with the action's own color, shaded the same
    /// way.
    private func applyGlass() {
        let glass = UIGlassEffect(style: .clear)
        glass.isInteractive = true
        let fill = tint.picked ?? (isCommitted ? color : nil)
        glass.tintColor = fill?.shadedFill.withAlphaComponent(isCommitted ? 0.9 : 0.8)
        effectView.effect = glass
        imageView.tintColor = fill?.shadedSymbol ?? .label
        titleLabel.textColor = imageView.tintColor
    }

    /// The symbol alone in the middle; once wide enough, the symbol and title side by side, centered together.
    override func layoutSubviews() {
        super.layoutSubviews()
        // The symbol keeps its place while a box stands in for it, so the box sits where the symbol was.
        let symbol = imageView.intrinsicContentSize
        let titled = bounds.width >= Self.titledWidth
        let title = titleLabel.intrinsicContentSize
        let gap: CGFloat = 8
        let available = bounds.width - 2 * SwipeLayout.spacing - symbol.width - gap
        let titleWidth = titled ? min(title.width, max(0, available)) : 0
        let total = symbol.width + (titled ? gap + titleWidth : 0)
        let start = (bounds.width - total) / 2
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let symbolX = isRightToLeft ? start + total - symbol.width : start
        imageView.frame = CGRect(
            x: symbolX, y: (bounds.height - symbol.height) / 2, width: symbol.width, height: symbol.height)
        titleLabel.frame = CGRect(
            x: isRightToLeft ? start : symbolX + symbol.width + gap, y: (bounds.height - title.height) / 2,
            width: titleWidth, height: title.height)
        titleLabel.alpha = titled ? 1 : 0
        box?.center = imageView.center
    }

    /// Where the symbol sits, in the button's coordinates.
    var symbolCenter: CGPoint { imageView.center }

    /// Swaps the symbol for a drawn `kind` box whose lid can open, in the symbol's color.
    func showBox(_ kind: StowKind) -> StowBoxView {
        let box = StowBoxView(kind: kind, color: imageView.tintColor)
        box.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        box.center = imageView.center
        // Hidden rather than cleared: an image view without an image has no size, and the layout places the box by it.
        imageView.alpha = 0
        effectView.contentView.addSubview(box)
        self.box = box
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
