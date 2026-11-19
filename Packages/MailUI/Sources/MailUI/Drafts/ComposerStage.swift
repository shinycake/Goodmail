import MailCore
import UIKit

/// Moves the composer's card between the screen, the bar and away, one motion at a time. Everything that moves with
/// it (the card, the mail screens making room for the bar, the bar, the dimming) moves in one animator, so the motion
/// is a single piece. A drag on the card or on the bar scrubs that animator under the finger; letting go, or a tap,
/// hands it to a spring.
final class ComposerStage: NSObject {
    /// Where a card leaving the screen goes.
    enum Destination {
        /// Into the bar, as a minimized message.
        case bar
        /// Off the bottom of the screen: sent, saved away or discarded.
        case away
    }

    /// Where a card coming onto the screen starts.
    enum Origin {
        /// The bar, for a minimized message coming back.
        case bar
        /// Below the screen, for a new message.
        case below
    }

    /// A card about to leave under the finger: where it goes, whether the bar shows once it's gone, and what to do
    /// once it lands, `true` there or `false` back on the screen.
    struct Leaving {
        let destination: Destination
        let barShowing: Bool
        let landed: (Bool) -> Void
    }

    /// Asked as a drag down on the card begins: how the message leaves, or `nil` to keep it.
    var planLeaving: ((ComposeViewController) -> Leaving?)?

    /// The composer on the screen or on its way, if any.
    var composer: ComposeViewController? {
        switch motion {
        case .idle: nil
        case .open(let composer): composer
        case .moving(let move): move.composer
        }
    }

    var isMoving: Bool {
        if case .moving = motion { true } else { false }
    }

    /// The card's motion. Only `begin` and `land` change it.
    private var motion = Motion.idle

    private enum Motion {
        /// No composer on the screen.
        case idle
        /// The composer fills the card, at rest.
        case open(ComposeViewController)
        /// The card on its way, under the finger or settling.
        case moving(Move)
    }

    private struct Move {
        let composer: ComposeViewController
        let direction: Direction
        let animation: ScrubbedAnimation
        /// Whether the bar showed before, to put it back that way if the card goes back.
        let barWasShowing: Bool
        let landed: (Bool) -> Void
    }

    private enum Direction {
        case opening
        case leaving(Destination)
    }

    private unowned let shelf: UIViewController
    private let bar: UIView
    /// Fits the mail screens above the bar when it shows, or to the bottom of the screen.
    private let layOutContent: (Bool) -> Void
    private let card = ComposerCardView()
    private let dimming = UIView()
    private let cardPan = UIPanGestureRecognizer()

    init(shelf: UIViewController, bar: UIView, layOutContent: @escaping (Bool) -> Void) {
        self.shelf = shelf
        self.bar = bar
        self.layOutContent = layOutContent
        super.init()
        dimming.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimming.isHidden = true
        card.isHidden = true
        card.onMinimize = { [weak self] in self?.composer?.minimize() }
        cardPan.addTarget(self, action: #selector(cardPanned(_:)))
        cardPan.delegate = self
        card.addGestureRecognizer(cardPan)
    }

    /// Puts the dimming and the card over the mail screens and the bar.
    func install() {
        dimming.frame = shelf.view.bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shelf.view.addSubview(dimming)
        shelf.view.addSubview(card)
    }

    /// Keeps an open card filling the screen as the window changes size.
    func layout() {
        guard case .open(let composer) = motion, let navigation = composer.navigationController else { return }
        card.frame = openFrame
        navigation.view.frame = CGRect(
            x: 0, y: ComposerCardView.grabberRoom, width: card.bounds.width,
            height: card.bounds.height - ComposerCardView.grabberRoom)
    }

    // MARK: Moving

    /// Brings `composer` onto the screen from `origin`, following `pan` if a finger is dragging it there. `barShowing`
    /// is whether the bar shows behind the open card.
    func open(
        _ composer: ComposeViewController, from origin: Origin, barShowing: Bool,
        following pan: UIPanGestureRecognizer? = nil, landed: @escaping (Bool) -> Void = { _ in }
    ) {
        settleNow()
        let navigation = composer.navigationController ?? UINavigationController(rootViewController: composer)
        // As a sheet would be: lifted off the screen behind it.
        navigation.traitOverrides.userInterfaceLevel = .elevated
        let open = openFrame
        let start: CGRect =
            switch origin {
            case .bar: bar.frame
            case .below: open.offsetBy(dx: 0, dy: shelf.view.bounds.height - open.minY)
            }
        shelf.addChild(navigation)
        card.hold(navigation.view, openSize: open.size)
        navigation.didMove(toParent: shelf)
        // Scrolling waits to see whether a drag down at the top of the message takes the card down instead.
        composer.scrollPan.require(toFail: cardPan)
        card.frame = start
        card.isHidden = false
        card.layer.cornerRadius = origin == .bar ? MinimizedDraftsBar.cornerRadius : ComposerCardView.openCornerRadius
        card.content.alpha = origin == .bar ? 0 : 1
        // From the bar, the card rises out of it: it fades in over the bar as it starts to grow.
        card.alpha = origin == .bar ? 0 : 1
        dimming.isHidden = false
        dimming.alpha = 0
        bar.isHidden = false
        let fromBar = origin == .bar
        let barWasShowing = bar.alpha > 0
        begin(
            Move(
                composer: composer, direction: .opening,
                animation: animation(distance: start.minY - open.minY, heading: .up) {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                        self.card.frame = open
                        self.card.layer.cornerRadius = ComposerCardView.openCornerRadius
                        self.dimming.alpha = 1
                        self.layOutContent(barShowing)
                        self.shelf.view.layoutIfNeeded()
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: fromBar ? 0.4 : 1) {
                        self.bar.alpha = barShowing ? 1 : 0
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.2) {
                        self.card.alpha = 1
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.15, relativeDuration: 0.45) {
                        self.card.content.alpha = 1
                    }
                },
                barWasShowing: barWasShowing, landed: landed),
            following: pan)
    }

    /// Takes the open card to `destination`. `barShowing` is whether the bar shows once it's gone.
    func leave(to destination: Destination, barShowing: Bool, landed: @escaping (Bool) -> Void = { _ in }) {
        settleNow()
        guard case .open(let composer) = motion else { return landed(true) }
        begin(leaving(composer, to: destination, barShowing: barShowing, landed: landed), following: nil)
    }

    private func leaving(
        _ composer: ComposeViewController, to destination: Destination, barShowing: Bool,
        landed: @escaping (Bool) -> Void
    ) -> Move {
        let open = card.frame
        let end: CGRect =
            switch destination {
            case .bar: bar.frame
            case .away: open.offsetBy(dx: 0, dy: shelf.view.bounds.height - open.minY)
            }
        bar.isHidden = false
        let intoBar = destination == .bar
        let barWasShowing = bar.alpha > 0
        return Move(
            composer: composer, direction: .leaving(destination),
            animation: animation(distance: end.minY - open.minY, heading: .down) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                    self.card.frame = end
                    if intoBar { self.card.layer.cornerRadius = MinimizedDraftsBar.cornerRadius }
                    self.dimming.alpha = 0
                    self.layOutContent(barShowing)
                    self.shelf.view.layoutIfNeeded()
                }
                if intoBar {
                    UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.45) {
                        self.card.content.alpha = 0
                    }
                    // Over the bar, the card gives way to it, so the bar is what's there when it lands.
                    UIView.addKeyframe(withRelativeStartTime: 0.8, relativeDuration: 0.2) {
                        self.card.alpha = 0
                    }
                }
                UIView.addKeyframe(withRelativeStartTime: intoBar ? 0.55 : 0, relativeDuration: intoBar ? 0.45 : 1) {
                    self.bar.alpha = barShowing ? 1 : 0
                }
            },
            barWasShowing: barWasShowing, landed: landed)
    }

    /// One motion for everything that moves: `keyframes` run over its length, each piece at its own part of it.
    private func animation(distance: CGFloat, heading: ScrubbedAnimation.Heading, keyframes: @escaping () -> Void)
        -> ScrubbedAnimation
    {
        ScrubbedAnimation(
            distance: distance, heading: heading, in: shelf.view,
            animations: {
                UIView.animateKeyframes(withDuration: 0, delay: 0, options: [.calculationModeLinear]) { keyframes() }
            },
            landed: { [weak self] arrived in self?.land(arrived: arrived) })
    }

    private func begin(_ move: Move, following pan: UIPanGestureRecognizer?) {
        motion = .moving(move)
        move.animation.run(following: pan)
    }

    /// Finishes a motion under way at once, as when another message opens before it's done.
    private func settleNow() {
        guard case .moving(let move) = motion else { return }
        move.animation.finishNow()
    }

    /// The motion came to rest at its end, or back where it started.
    private func land(arrived: Bool) {
        guard case .moving(let move) = motion else { return }
        let onScreen: Bool =
            switch move.direction {
            case .opening: arrived
            case .leaving: !arrived
            }
        if onScreen {
            motion = .open(move.composer)
            card.frame = openFrame
            card.layer.cornerRadius = ComposerCardView.openCornerRadius
            card.content.alpha = 1
            card.alpha = 1
            dimming.alpha = 1
        } else {
            motion = .idle
            remove(move.composer)
        }
        if !arrived {
            // The constraints moved with the animation; they go back with the frames.
            layOutContent(move.barWasShowing)
            bar.alpha = move.barWasShowing ? 1 : 0
        }
        bar.isHidden = bar.alpha == 0
        if case .opening = move.direction, arrived { move.composer.didOpen() }
        move.landed(arrived)
    }

    private func remove(_ composer: ComposeViewController) {
        card.isHidden = true
        card.alpha = 1
        dimming.isHidden = true
        guard let navigation = composer.navigationController else { return }
        navigation.willMove(toParent: nil)
        navigation.view.removeFromSuperview()
        navigation.removeFromParent()
    }

    // MARK: Dragging the card down

    @objc private func cardPanned(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .began, case .open(let composer) = motion, let plan = planLeaving?(composer) else { return }
        begin(
            leaving(composer, to: plan.destination, barShowing: plan.barShowing, landed: plan.landed), following: pan)
    }

    // MARK: Geometry

    /// The card filling the screen, below the status bar as a sheet would be; a readable width on a wide window.
    /// Kept to the fold lane, as the bar is, so it shrinks straight down into it on iPhone Duo.
    private var openFrame: CGRect {
        let lane = shelf.view.foldLane
        let top = shelf.view.safeAreaInsets.top + (isWide ? 24 : 8)
        let width = isWide ? min(lane.width - 80, 720) : lane.width
        return CGRect(x: lane.midX - width / 2, y: top, width: width, height: shelf.view.bounds.maxY - top)
    }

    private var isWide: Bool { shelf.traitCollection.horizontalSizeClass == .regular }
}

extension ComposerStage: UIGestureRecognizerDelegate {
    /// A drag down on the card's header, or anywhere once the message is scrolled to its top, takes the card down.
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === cardPan, case .open(let composer) = motion else { return false }
        let velocity = cardPan.velocity(in: card)
        guard velocity.y > 0, velocity.y > abs(velocity.x) else { return false }
        let header = composer.navigationController.map {
            $0.navigationBar.convert($0.navigationBar.bounds, to: card).maxY
        }
        return composer.isScrolledToTop || cardPan.location(in: card).y < header ?? ComposerCardView.grabberRoom
    }
}
