import MailCore
import UIKit

/// Moves the composer's card between the screen, the drafts pill and away, one leg at a time. The card is the live
/// composer, scaled inside a shrinking shape: minimizing shrinks it onto the pill's place as an opaque chip, the pill
/// changes under it, and the chip drains into the pill's icon, uncovering the glass. Opening is the same backward.
/// A drag on the card scrubs the leg under the finger; letting go, or a tap, hands it to a spring.
final class ComposerStage: NSObject {
    /// Where a card leaving the screen goes.
    enum Destination {
        /// Into the drafts pill, or out by its corner of the screen when no pill is on show. `docked` runs once, when
        /// the pill may show the message: it marks it minimized and must not call back into the stage.
        case dock(docked: () -> Void)
        /// Off the bottom of the screen: sent, saved away or discarded.
        case away
    }

    /// Where a card coming onto the screen starts.
    enum Origin {
        /// Out of the drafts pill. `undocked` runs once, when the pill may let the message go; same rule as `docked`.
        case dock(undocked: () -> Void)
        /// Below the screen, for a new message.
        case below
    }

    /// A card about to leave under the finger, and what to do once it comes to rest: `true` gone, `false` back.
    struct Leaving {
        let destination: Destination
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

    /// The card's motion. Only `begin` and `land` change it.
    private var motion = Motion.idle

    private enum Motion {
        /// No composer on the screen.
        case idle
        /// The composer fills the card, at rest.
        case open(ComposeViewController)
        /// The card on one leg of its way, under the finger or settling.
        case moving(Move)
    }

    private struct Move {
        let composer: ComposeViewController
        let leg: Leg
        let animation: ScrubbedAnimation
    }

    private enum Leg {
        /// A dot grows out of the pill's icon until the card covers the pill. Then the pill lets the message go.
        case lifting(PillSpot, undocked: () -> Void)
        /// Onto the screen, from the pill, the corner or below.
        case opening
        /// Off the screen to `landing`.
        case leaving(Landing, landed: (Bool) -> Void)
        /// Into the pill's icon, once the pill shows the message.
        case draining(PillSpot)
    }

    /// Where a leaving card comes to rest.
    private enum Landing {
        /// Over the pill, as the chip.
        case pill(PillSpot, docked: () -> Void)
        /// Off the screen at `frame`, minimized: by the pill's corner, or straight down with Reduce Motion.
        case offscreen(CGRect, docked: () -> Void)
        /// Off the bottom at `frame`, done with.
        case away(CGRect)

        var frame: CGRect {
            switch self {
            case .pill(let spot, _): spot.frame
            case .offscreen(let frame, _), .away(let frame): frame
            }
        }
    }

    /// How long each leg takes. Every one is critically damped, so the card never overshoots the pill and uncovers
    /// it early.
    private enum Timing {
        /// Below to open, and away.
        static let slide: TimeInterval = 0.5
        /// Open to the chip or the corner.
        static let shrink: TimeInterval = 0.42
        /// The chip into the icon.
        static let drain: TimeInterval = 0.2
        /// The icon out to the chip.
        static let lift: TimeInterval = 0.14
        /// The chip or the corner to open.
        static let grow: TimeInterval = 0.46
    }

    /// The radius of the dot at the pill's icon.
    private static let dotRadius: CGFloat = 3

    private unowned let shelf: UIViewController
    private let dock: DraftsDock
    private let card = ComposerCardView()
    private let dimming = UIView()
    private let cardPan = UIPanGestureRecognizer()

    init(shelf: UIViewController, dock: DraftsDock) {
        self.shelf = shelf
        self.dock = dock
        super.init()
        dimming.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimming.isHidden = true
        card.isHidden = true
        card.onMinimize = { [weak self] in self?.composer?.minimize() }
        cardPan.addTarget(self, action: #selector(cardPanned(_:)))
        cardPan.delegate = self
        card.addGestureRecognizer(cardPan)
    }

    /// Puts the dimming and the card over the mail screens.
    func install() {
        dimming.frame = shelf.view.bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shelf.view.addSubview(dimming)
        shelf.view.addSubview(card)
    }

    /// Keeps an open card filling the screen as the window changes size.
    func layout() {
        guard case .open(let composer) = motion, let navigation = composer.navigationController else { return }
        let open = openFrame
        card.hold(navigation.view, openSize: open.size)
        card.refit(open, cornerRadius: ComposerCardView.openCornerRadius)
    }

    // MARK: Moving

    /// Brings `composer` onto the screen from `origin`.
    func open(_ composer: ComposeViewController, from origin: Origin) {
        settleNow()
        clearLeftover()
        let navigation = composer.navigationController ?? UINavigationController(rootViewController: composer)
        shelf.addChild(navigation)
        card.hold(navigation.view, openSize: openFrame.size)
        navigation.didMove(toParent: shelf)
        // Scrolling waits to see whether a drag down at the top of the message takes the card down instead.
        composer.scrollPan.require(toFail: cardPan)
        card.isHidden = false
        dimming.isHidden = false
        dimming.alpha = 0
        switch origin {
        case .below:
            start(at: below, cornerRadius: ComposerCardView.openCornerRadius)
            begin(opening(composer, duration: Timing.slide), following: nil)
        case .dock(let undocked):
            if SystemAccessibility.reducesMotion {
                undocked()
                start(at: below, cornerRadius: ComposerCardView.openCornerRadius)
                begin(opening(composer, duration: Timing.slide), following: nil)
            } else if let spot = dock.shownPill?.spot(in: shelf.view, showing: dock.count) {
                card.cornerCurve = .circular
                card.fit(DraftsPillPlacement.dot(at: spot.icon), cornerRadius: Self.dotRadius)
                begin(lifting(composer, out: spot, undocked: undocked), following: nil)
            } else {
                undocked()
                start(at: corner, cornerRadius: DraftsPillPlacement.chipSize.height / 2)
                begin(opening(composer, duration: Timing.grow), following: nil)
            }
        }
    }

    /// Takes `composer`'s card to `destination` once it is open. When settling what is under way leaves another
    /// message on the stage, as one opened once the last move landed, `composer` has already gone and only `landed`
    /// runs.
    func leave(
        _ composer: ComposeViewController, to destination: Destination, landed: @escaping (Bool) -> Void = { _ in }
    ) {
        settleNow()
        guard case .open(let open) = motion, open === composer else { return landed(true) }
        begin(leaving(composer, Leaving(destination: destination, landed: landed)), following: nil)
    }

    /// Finishes the message's motion under way at once, every leg of it at its end: a minimize ends minimized, an
    /// open ends open. A message that a landing opens moves on its own.
    func settleNow() {
        guard case .moving(let first) = motion else { return }
        while case .moving(let move) = motion, move.composer === first.composer {
            move.animation.finishNow()
            // Each leg lands as it finishes; one that didn't would otherwise be finished forever.
            if case .moving(let next) = motion, next.animation === move.animation { return }
        }
    }

    /// Finishes everything under way at once, a message that a landing opens too, as before the window changes size.
    func settleEverything() {
        while case .moving(let move) = motion {
            settleNow()
            if case .moving(let next) = motion, next.animation === move.animation { return }
        }
    }

    /// The shelf minimizes the message being written before it opens another, so the stage is empty by the time one
    /// opens. A message still on it would stay stuck under the new card: it is taken off.
    private func clearLeftover() {
        guard let leftover = composer else { return }
        assertionFailure("A message opened while another was still on the stage")
        if case .moving(let move) = motion {
            // Idle first, so the leg lands on nothing.
            motion = .idle
            move.animation.finishNow()
        }
        clear(leftover)
    }

    /// Poses the card at a start that keeps its corners continuous, as an open card's are.
    private func start(at frame: CGRect, cornerRadius: CGFloat) {
        card.cornerCurve = .continuous
        card.fit(frame, cornerRadius: cornerRadius)
    }

    private func lifting(_ composer: ComposeViewController, out spot: PillSpot, undocked: @escaping () -> Void)
        -> Move
    {
        Move(
            composer: composer, leg: .lifting(spot, undocked: undocked),
            animation: animation(distance: 0, heading: .up, duration: Timing.lift) {
                self.card.fit(spot.frame, cornerRadius: spot.frame.height / 2)
            })
    }

    private func opening(_ composer: ComposeViewController, duration: TimeInterval) -> Move {
        let open = openFrame
        return Move(
            composer: composer, leg: .opening,
            animation: animation(distance: 0, heading: .up, duration: duration) {
                self.card.fit(open, cornerRadius: ComposerCardView.openCornerRadius)
                self.dimming.alpha = 1
            })
    }

    /// The open card on its way to where `leaving` sends it. A card that keeps its size slides; one that shrinks
    /// turns into a capsule as it goes.
    private func leaving(_ composer: ComposeViewController, _ leaving: Leaving) -> Move {
        let landing = landing(for: leaving.destination)
        let target = landing.frame
        let slides = target.size == card.frame.size
        if case .pill = landing { card.cornerCurve = .circular }
        let radius = slides ? ComposerCardView.openCornerRadius : target.height / 2
        return Move(
            composer: composer, leg: .leaving(landing, landed: leaving.landed),
            animation: animation(
                distance: target.minY - card.frame.minY, heading: .down,
                duration: slides ? Timing.slide : Timing.shrink
            ) {
                self.card.fit(target, cornerRadius: radius)
                self.dimming.alpha = 0
            })
    }

    private func draining(_ composer: ComposeViewController, into spot: PillSpot) -> Move {
        Move(
            composer: composer, leg: .draining(spot),
            animation: animation(distance: 0, heading: .down, duration: Timing.drain) {
                self.card.fit(DraftsPillPlacement.dot(at: spot.icon), cornerRadius: Self.dotRadius)
            })
    }

    /// Where a card leaving for `destination` comes to rest, measured as it sets off.
    private func landing(for destination: Destination) -> Landing {
        switch destination {
        case .away:
            return .away(below)
        case .dock(let docked):
            if SystemAccessibility.reducesMotion { return .offscreen(below, docked: docked) }
            // The message leaving isn't counted until it's docked.
            if let spot = dock.shownPill?.spot(in: shelf.view, showing: dock.count + 1) {
                return .pill(spot, docked: docked)
            }
            return .offscreen(corner, docked: docked)
        }
    }

    private func animation(
        distance: CGFloat, heading: ScrubbedAnimation.Heading, duration: TimeInterval,
        animations: @escaping () -> Void
    ) -> ScrubbedAnimation {
        ScrubbedAnimation(
            distance: distance, heading: heading, in: shelf.view, duration: duration, animations: animations,
            landed: { [weak self] arrived in self?.land(arrived: arrived) })
    }

    private func begin(_ move: Move, following pan: UIPanGestureRecognizer?) {
        // Set before the animation runs, so by the time anything lands the state is already the next one.
        motion = .moving(move)
        move.animation.run(following: pan)
    }

    /// A leg came to rest at its end, or back where it started: the one place a leg ends and the next begins.
    private func land(arrived: Bool) {
        guard case .moving(let move) = motion else { return }
        let composer = move.composer
        switch move.leg {
        case .lifting(_, let undocked):
            // The pill hides, or counts one fewer, under the chip. The chip's corners turn continuous while it is
            // still the pill's size, as an open card's are, so they don't change as it comes to rest.
            undocked()
            card.cornerCurve = .continuous
            begin(opening(composer, duration: Timing.grow), following: nil)
        case .opening:
            // Nothing follows a finger onto the screen, so an opening always arrives.
            assert(arrived, "An opening came back")
            rest(composer)
            composer.didOpen()
        case .leaving(let landing, let landed):
            guard arrived else {
                rest(composer)
                return landed(false)
            }
            switch landing {
            case .pill(let spot, let docked):
                // The pill shows the message, under the chip, which then lies exactly on it.
                docked()
                let spot = spot.pill.spot(in: shelf.view, showing: dock.count) ?? spot
                UIView.performWithoutAnimation { card.fit(spot.frame, cornerRadius: spot.frame.height / 2) }
                begin(draining(composer, into: spot), following: nil)
            case .offscreen(_, let docked):
                clear(composer)
                docked()
            case .away:
                clear(composer)
            }
            // May open another message, which settles the drain at once.
            landed(true)
        case .draining(let spot):
            clear(composer)
            spot.pill.bounce()
        }
    }

    /// The composer fills the card, at rest.
    private func rest(_ composer: ComposeViewController) {
        motion = .open(composer)
        card.cornerCurve = .continuous
        dimming.alpha = 1
        layout()
    }

    /// Nothing on the screen: the card and the dimming hidden, the composer taken out of the card.
    private func clear(_ composer: ComposeViewController) {
        motion = .idle
        card.isHidden = true
        dimming.isHidden = true
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

    /// The card filling the screen, below the status bar as a sheet would be; a readable width on a wide window.
    /// Kept to the fold lane, so it shrinks straight down on iPhone Duo. It reaches `overhang` below the screen, so
    /// its bottom corners are rounded out of sight.
    private var openFrame: CGRect {
        let lane = shelf.view.foldLane
        let top = shelf.view.safeAreaInsets.top + (isWide ? 24 : 8)
        let width = isWide ? min(lane.width - 80, 720) : lane.width
        return CGRect(
            x: lane.midX - width / 2, y: top, width: width,
            height: shelf.view.bounds.maxY - top + ComposerCardView.overhang)
    }

    /// The open card moved down until its top is at the bottom of the screen.
    private var below: CGRect {
        let open = openFrame
        return open.offsetBy(dx: 0, dy: shelf.view.bounds.maxY - open.minY)
    }

    /// Where a minimized card goes, or a reopened one comes from, when no pill is on show.
    private var corner: CGRect {
        DraftsPillPlacement.corner(
            lane: shelf.view.foldLane, bounds: shelf.view.bounds,
            rightToLeft: shelf.view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
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
