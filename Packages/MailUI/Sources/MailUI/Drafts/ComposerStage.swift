import MailCore
import UIKit

/// Moves the composer's card between the screen, the bar of minimized messages and away, one motion at a time.
/// Everything on the card (its frame, the composer scaling inside it, the grabber, the dimming) moves in one animator,
/// so the motion is a single piece that ends as the bar itself. A drag on the card or on the bar scrubs that animator
/// under the finger; letting go, or a tap, hands it to a spring. The mail screens make room for the bar, or take it
/// back, as the motion is let go toward its end (`Leaving.headed`), outside the animator the finger holds, so their
/// toolbars never lay out under a paused animator. The keyboard runs outside the app, where it can't be pictured or
/// moved, so it slides away on its own as the card sets off.
final class ComposerStage: NSObject {
    /// Where a card leaving the screen goes.
    enum Destination {
        /// Into the bar, which then shows `drafts`, the last one written first.
        case bar(showing: [Draft])
        /// Off the bottom of the screen: sent, saved away or discarded.
        case away
    }

    /// Where a card coming onto the screen starts.
    enum Origin {
        /// The bar, showing `drafts`, for one of them coming back.
        case bar(showing: [Draft])
        /// Below the screen, for a new message.
        case below
    }

    /// A card about to leave under the finger: where it goes, what to do once it's let go toward there (`true`) or
    /// back, and once it lands, `true` there or `false` back on the screen.
    struct Leaving {
        let destination: Destination
        var headed: (Bool) -> Void = { _ in }
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
        let landed: (Bool) -> Void
    }

    private enum Direction {
        case opening
        case leaving
    }

    private unowned let shelf: UIViewController
    /// The bar of minimized messages, which a card minimizing ends as and one coming back starts from.
    private unowned let bar: UIView
    private let card = ComposerCardView()
    private let backdrop = ComposerBackdropView()
    private let cardPan = UIPanGestureRecognizer()

    init(shelf: UIViewController, bar: UIView) {
        self.shelf = shelf
        self.bar = bar
        super.init()
        backdrop.isHidden = true
        card.isHidden = true
        card.onMinimize = { [weak self] in self?.composer?.minimize() }
        cardPan.addTarget(self, action: #selector(cardPanned(_:)))
        cardPan.delegate = self
        card.addGestureRecognizer(cardPan)
    }

    /// Puts the backdrop and the card over the mail screens and the bar.
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

    /// Brings `composer` onto the screen from `origin`, following `pan` if a finger is dragging it there. `headed`
    /// hears whether it's let go toward the screen, `landed` whether it got there.
    func open(
        _ composer: ComposeViewController, from origin: Origin, following pan: UIPanGestureRecognizer? = nil,
        headed: @escaping (Bool) -> Void = { _ in }, landed: @escaping (Bool) -> Void = { _ in }
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
        case .bar(let drafts):
            // The minimize run backward: the bar grows into the composer.
            card.face.show(drafts)
            let start = barFrame
            pose(minimized: start)
            animation = self.animation(distance: start.minY - open.minY, heading: .up, headed: headed) {
                self.keyframe(MinimizeMorph.shrink.mirrored) {
                    self.card.fit(open, cornerRadius: ComposerCardView.openCornerRadius)
                    self.backdrop.dimming = 1
                }
                self.keyframe(MinimizeMorph.composer.mirrored) { self.card.composerAlpha = 1 }
                self.keyframe(MinimizeMorph.curtain.mirrored) { self.backdrop.curtainAlpha = 1 }
            }
        case .below:
            let start = open.offsetBy(dx: 0, dy: shelf.view.bounds.height - open.minY)
            pose(sliding: start)
            animation = self.animation(distance: start.minY - open.minY, heading: .up, headed: headed) {
                self.keyframe(MinimizeMorph.shrink) { self.poseOpen(open) }
            }
        }
        begin(Move(composer: composer, direction: .opening, animation: animation, landed: landed), following: pan)
    }

    /// Takes the open card to `destination`.
    func leave(
        to destination: Destination, headed: @escaping (Bool) -> Void = { _ in },
        landed: @escaping (Bool) -> Void = { _ in }
    ) {
        settleNow()
        guard case .open(let composer) = motion else {
            headed(true)
            return landed(true)
        }
        begin(leaving(composer, Leaving(destination: destination, headed: headed, landed: landed)), following: nil)
    }

    private func leaving(_ composer: ComposeViewController, _ leaving: Leaving) -> Move {
        let headed = leaving.headed
        let from = card.frame
        let animation: ScrubbedAnimation
        switch leaving.destination {
        case .bar(let drafts):
            card.face.show(drafts)
            let end = barFrame
            animation = self.animation(distance: end.minY - from.minY, heading: .down, headed: headed) {
                self.keyframe(MinimizeMorph.shrink) {
                    self.card.fit(end, cornerRadius: MinimizedDraftsBar.cornerRadius)
                    self.backdrop.dimming = 0
                }
                self.keyframe(MinimizeMorph.curtain) { self.backdrop.curtainAlpha = 0 }
                self.keyframe(MinimizeMorph.composer) { self.card.composerAlpha = 0 }
            }
        case .away:
            let end = from.offsetBy(dx: 0, dy: shelf.view.bounds.height - from.minY)
            animation = self.animation(distance: end.minY - from.minY, heading: .down, headed: headed) {
                self.keyframe(MinimizeMorph.shrink) { self.pose(sliding: end) }
            }
        }
        return Move(composer: composer, direction: .leaving, animation: animation, landed: leaving.landed)
    }

    /// The card open at `frame`, everything on it showing, the screens behind it dimmed.
    private func poseOpen(_ frame: CGRect) {
        card.fit(frame, cornerRadius: ComposerCardView.openCornerRadius)
        card.composerAlpha = 1
        backdrop.dimming = 1
        backdrop.curtainAlpha = 1
    }

    /// The card whole at `frame`, below the screen or on its way there, the screens behind it clear.
    private func pose(sliding frame: CGRect) {
        card.fit(frame, cornerRadius: ComposerCardView.openCornerRadius)
        card.composerAlpha = 1
        backdrop.dimming = 0
        backdrop.curtainAlpha = 0
    }

    /// The card as the bar at `frame`: only its face shows.
    private func pose(minimized frame: CGRect) {
        card.fit(frame, cornerRadius: MinimizedDraftsBar.cornerRadius)
        card.composerAlpha = 0
        backdrop.dimming = 0
        backdrop.curtainAlpha = 0
    }

    private func keyframe(_ span: MorphSpan, _ animations: @escaping () -> Void) {
        UIView.addKeyframe(withRelativeStartTime: span.start, relativeDuration: span.length, animations: animations)
    }

    /// One motion for everything that moves: `keyframes` run over its length, each piece at its own part of it.
    private func animation(
        distance: CGFloat, heading: ScrubbedAnimation.Heading, headed: @escaping (Bool) -> Void,
        keyframes: @escaping () -> Void
    ) -> ScrubbedAnimation {
        ScrubbedAnimation(
            distance: distance, heading: heading, in: shelf.view,
            animations: {
                UIView.animateKeyframes(withDuration: 0, delay: 0, options: [.calculationModeLinear]) { keyframes() }
            },
            headed: headed,
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
            card.refit(openFrame, cornerRadius: ComposerCardView.openCornerRadius)
            poseOpen(openFrame)
            // The window may have changed size on the way: the composer and the curtain fit it again.
            layout()
        } else {
            motion = .idle
            remove(move.composer)
        }
        if case .opening = move.direction, arrived { move.composer.didOpen() }
        move.landed(arrived)
    }

    private func remove(_ composer: ComposeViewController) {
        card.isHidden = true
        backdrop.isHidden = true
        guard let navigation = composer.navigationController else { return }
        navigation.willMove(toParent: nil)
        navigation.view.removeFromSuperview()
        navigation.removeFromParent()
    }

    // MARK: Dragging the card down

    @objc private func cardPanned(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .began, case .open(let composer) = motion, let plan = planLeaving?(composer) else { return }
        begin(leaving(composer, plan), following: pan)
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

    /// The bar, and past the bottom of the screen by the card's overhang, so the card turns into it with square
    /// bottom corners hidden off the screen, as the bar's are.
    private var barFrame: CGRect {
        let frame = bar.frame
        return CGRect(
            x: frame.minX, y: frame.minY, width: frame.width,
            height: shelf.view.bounds.maxY - frame.minY + ComposerCardView.overhang)
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
