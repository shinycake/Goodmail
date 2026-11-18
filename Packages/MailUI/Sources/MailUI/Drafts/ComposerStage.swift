import MailCore
import UIKit

/// Moves the composer's card between the screen, the minimized messages and away, one motion at a time. Everything
/// that moves with it (the card, the composer scaling inside it, the keyboard's picture, the dimming) moves in one
/// animator, so the motion is a single piece; the mail screens behind it never move. A drag on the card or on the
/// minimized messages scrubs that animator under the finger; letting go, or a tap, hands it to a spring.
final class ComposerStage: NSObject {
    /// Where a card leaving the screen goes.
    enum Destination {
        /// Into the minimized messages, which then show `drafts`, the last one written first.
        case dock(showing: [Draft])
        /// Off the bottom of the screen: sent, saved away or discarded.
        case away
    }

    /// Where a card coming onto the screen starts.
    enum Origin {
        /// The minimized messages, showing `drafts`, for one of them coming back.
        case dock(showing: [Draft])
        /// Below the screen, for a new message.
        case below
    }

    /// A card about to leave under the finger: where it goes, and what to do once it lands, `true` there or `false`
    /// back on the screen.
    struct Leaving {
        let destination: Destination
        let landed: (Bool) -> Void
    }

    /// Asked as a drag down on the card begins: how the message leaves, or `nil` to keep it.
    var planLeaving: ((ComposeViewController) -> Leaving?)?
    /// Told as a motion begins and as it lands: which composer is on the card changed.
    var onChange: (() -> Void)?

    /// The composer on the screen or on its way, if any.
    var composer: ComposeViewController? {
        switch motion {
        case .idle: nil
        case .open(let composer): composer
        case .moving(let move): move.composer
        }
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
        let landed: (Bool) -> Void
    }

    private enum Direction {
        case opening
        case leaving
    }

    private unowned let shelf: UIViewController
    /// The minimized messages, which a card minimizing ends on and one coming back starts from.
    private unowned let dock: UIView
    private let card = ComposerCardView()
    private let backdrop = ComposerBackdropView()
    private let cardPan = UIPanGestureRecognizer()

    init(shelf: UIViewController, dock: UIView) {
        self.shelf = shelf
        self.dock = dock
        super.init()
        backdrop.isHidden = true
        card.isHidden = true
        card.onMinimize = { [weak self] in self?.composer?.minimize() }
        cardPan.addTarget(self, action: #selector(cardPanned(_:)))
        cardPan.delegate = self
        card.addGestureRecognizer(cardPan)
    }

    /// Puts the backdrop and the card over the mail screens and the minimized messages.
    func install() {
        backdrop.frame = shelf.view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shelf.view.addSubview(backdrop)
        shelf.view.addSubview(card)
    }

    /// Keeps an open card filling the screen as the window changes size.
    func layout() {
        guard case .open(let composer) = motion, let navigation = composer.navigationController else { return }
        let open = openFrame
        card.hold(navigation.view, openSize: open.size)
        card.fit(open, cornerRadius: ComposerCardView.openCornerRadius)
        backdrop.curtain(down: curtainBottom)
    }

    // MARK: Moving

    /// Brings `composer` onto the screen from `origin`, following `pan` if a finger is dragging it there.
    func open(
        _ composer: ComposeViewController, from origin: Origin, following pan: UIPanGestureRecognizer? = nil,
        landed: @escaping (Bool) -> Void = { _ in }
    ) {
        settleNow()
        let navigation = composer.navigationController ?? UINavigationController(rootViewController: composer)
        // As a sheet would be: lifted off the screen behind it.
        navigation.traitOverrides.userInterfaceLevel = .elevated
        let open = openFrame
        shelf.addChild(navigation)
        card.hold(navigation.view, openSize: open.size)
        navigation.didMove(toParent: shelf)
        // Scrolling waits to see whether a drag down at the top of the message takes the card down instead.
        composer.scrollPan.require(toFail: cardPan)
        card.isHidden = false
        backdrop.isHidden = false
        backdrop.curtain(down: curtainBottom)
        let animation: ScrubbedAnimation
        switch origin {
        case .dock(let drafts):
            // The minimize run backward: the capsule grows into the composer.
            card.face.show(drafts)
            let start = dock.frame
            pose(minimized: start)
            animation = self.animation(distance: start.minY - open.minY, heading: .up) {
                self.keyframe(MinimizeMorph.shrink.mirrored) {
                    self.card.fit(open, cornerRadius: ComposerCardView.openCornerRadius)
                    self.backdrop.dimming = 1
                }
                self.keyframe(MinimizeMorph.composer.mirrored) { self.card.composerAlpha = 1 }
                self.keyframe(MinimizeMorph.grabber.mirrored) { self.card.grabberAlpha = 1 }
                self.keyframe(MinimizeMorph.curtain.mirrored) { self.backdrop.curtainAlpha = 1 }
            }
        case .below:
            let start = open.offsetBy(dx: 0, dy: shelf.view.bounds.height - open.minY)
            pose(sliding: start)
            animation = self.animation(distance: start.minY - open.minY, heading: .up) {
                self.keyframe(MinimizeMorph.shrink) { self.poseOpen(open) }
            }
        }
        begin(Move(composer: composer, direction: .opening, animation: animation, landed: landed), following: pan)
    }

    /// Takes the open card to `destination`.
    func leave(to destination: Destination, landed: @escaping (Bool) -> Void = { _ in }) {
        settleNow()
        guard case .open(let composer) = motion else { return landed(true) }
        begin(leaving(composer, to: destination, landed: landed), following: nil)
    }

    private func leaving(
        _ composer: ComposeViewController, to destination: Destination, landed: @escaping (Bool) -> Void
    ) -> Move {
        let from = card.frame
        let animation: ScrubbedAnimation
        switch destination {
        case .dock(let drafts):
            card.face.show(drafts)
            let end = dock.frame
            animation = self.animation(distance: end.minY - from.minY, heading: .down) {
                self.keyframe(MinimizeMorph.shrink) {
                    self.card.fit(end, cornerRadius: end.height / 2)
                    self.backdrop.dimming = 0
                }
                self.keyframe(MinimizeMorph.curtain) { self.backdrop.curtainAlpha = 0 }
                self.keyframe(MinimizeMorph.grabber) { self.card.grabberAlpha = 0 }
                self.keyframe(MinimizeMorph.composer) { self.card.composerAlpha = 0 }
            }
        case .away:
            let end = from.offsetBy(dx: 0, dy: shelf.view.bounds.height - from.minY)
            animation = self.animation(distance: end.minY - from.minY, heading: .down) {
                self.keyframe(MinimizeMorph.shrink) { self.pose(sliding: end) }
            }
        }
        return Move(composer: composer, direction: .leaving, animation: animation, landed: landed)
    }

    /// The card open at `frame`, everything on it showing, the screens behind it dimmed.
    private func poseOpen(_ frame: CGRect) {
        card.fit(frame, cornerRadius: ComposerCardView.openCornerRadius)
        card.composerAlpha = 1
        card.grabberAlpha = 1
        backdrop.dimming = 1
        backdrop.curtainAlpha = 1
    }

    /// The card whole at `frame`, below the screen or on its way there, the screens behind it clear.
    private func pose(sliding frame: CGRect) {
        card.fit(frame, cornerRadius: ComposerCardView.openCornerRadius)
        card.composerAlpha = 1
        card.grabberAlpha = 1
        backdrop.dimming = 0
        backdrop.curtainAlpha = 0
    }

    /// The card as the minimized messages at `frame`: only its face shows.
    private func pose(minimized frame: CGRect) {
        card.fit(frame, cornerRadius: frame.height / 2)
        card.composerAlpha = 0
        card.grabberAlpha = 0
        backdrop.dimming = 0
        backdrop.curtainAlpha = 0
    }

    private func keyframe(_ span: MorphSpan, _ animations: @escaping () -> Void) {
        UIView.addKeyframe(withRelativeStartTime: span.start, relativeDuration: span.length, animations: animations)
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
        onChange?()
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
            poseOpen(openFrame)
        } else {
            motion = .idle
            remove(move.composer)
        }
        if case .opening = move.direction, arrived { move.composer.didOpen() }
        // Let go short, the composer takes the keyboard back first, where its picture stands, then lets go of it.
        move.landed(arrived)
        card.dropKeyboard()
        onChange?()
    }

    private func remove(_ composer: ComposeViewController) {
        card.isHidden = true
        backdrop.isHidden = true
        guard let navigation = composer.navigationController else { return }
        navigation.willMove(toParent: nil)
        navigation.view.removeFromSuperview()
        navigation.removeFromParent()
    }

    // MARK: The keyboard

    /// Before the open card sets off with `composer`, takes a picture of the keyboard, and the formatting controls on
    /// it, for the card to carry down: the keyboard can't follow a finger, and the minimized messages sit under it.
    /// Only when the window fills the screen, as the picture is of the screen.
    func carryKeyboard(of composer: ComposeViewController) {
        guard case .open(let open) = motion, open === composer, let window = card.window,
            let screen = window.windowScene?.screen, window.frame == screen.bounds
        else { return }
        let view = composer.view!
        let keyboard = view.keyboardLayoutGuide.layoutFrame
        guard keyboard.height > view.safeAreaInsets.bottom + 1 else { return }
        let picture = screen.snapshotView(afterScreenUpdates: false)
        let onScreen = view.convert(keyboard, to: window)
        let standIn = UIView()
        standIn.clipsToBounds = true
        standIn.isUserInteractionEnabled = false
        picture.frame.origin = CGPoint(x: -onScreen.minX, y: -onScreen.minY)
        standIn.addSubview(picture)
        card.carryKeyboard(standIn, at: keyboard, in: view)
    }

    // MARK: Dragging the card down

    @objc private func cardPanned(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .began, case .open(let composer) = motion, let plan = planLeaving?(composer) else { return }
        begin(leaving(composer, to: plan.destination, landed: plan.landed), following: pan)
    }

    // MARK: Geometry

    /// The card filling the screen, below the status bar as a sheet would be, and past the bottom by its overhang; a
    /// readable width on a wide window, below the screens' top buttons. Kept to the fold lane, as the minimized
    /// messages are, so it shrinks straight down into them on iPhone Duo.
    private var openFrame: CGRect {
        let lane = shelf.view.foldLane
        let top = shelf.view.safeAreaInsets.top + (isWide ? 64 : 8)
        let width = isWide ? min(lane.width - 80, 720) : lane.width
        return CGRect(
            x: lane.midX - width / 2, y: top, width: width,
            height: shelf.view.bounds.maxY - top + ComposerCardView.overhang)
    }

    /// Where the curtain over the screens' top buttons ends on a narrow window: under the open card's corners.
    private var curtainBottom: CGFloat? {
        isWide ? nil : openFrame.minY + ComposerCardView.openCornerRadius
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
