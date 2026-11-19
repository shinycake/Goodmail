import MailCore
import UIKit

/// Moves the composer's card between the screen, the drafts pill and away, in one motion each way. The card is the
/// live composer, scaled inside a shrinking shape. Minimizing shrinks it toward the pill and thins it out over the
/// last stretch, so the real pill underneath shows through; the pill already counts the message, having changed
/// under the open card as it set off. Opening is the same backward, out of the pill or out of a laid-out draft's
/// card. A drag on the card scrubs the motion under the finger; letting go, or a tap, hands it to a spring.
final class ComposerStage: NSObject {
    /// Where a card leaving the screen goes.
    enum Destination {
        /// Into the drafts pill, or out by its corner of the screen when no pill is on show. `docked` runs once, as
        /// the card lands: it marks the message minimized and must not call back into the stage.
        case dock(docked: () -> Void)
        /// Off the bottom of the screen: sent, saved away or discarded.
        case away
    }

    /// Where a card coming onto the screen starts. `undocked` runs once, as the card lands open, so the pill lets the
    /// message go under it; same rule as `docked`.
    enum Origin {
        /// Out of the drafts pill, or its corner when no pill is on show.
        case dock(undocked: () -> Void)
        /// Out of a laid-out draft's card at `frame`, in the shelf's view, with corners of `cornerRadius`.
        case card(CGRect, cornerRadius: CGFloat, undocked: () -> Void)
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
        /// The card on its way, under the finger or settling.
        case moving(Move)
    }

    private struct Move {
        let composer: ComposeViewController
        let leg: Leg
        let animation: ScrubbedAnimation
    }

    private enum Leg {
        /// Onto the screen. `arrived` runs as it lands.
        case opening(arrived: () -> Void)
        /// Off the screen to `landing`.
        case leaving(Landing, landed: (Bool) -> Void)
    }

    /// Where a leaving card comes to rest.
    private enum Landing {
        /// Onto the pill, thinning out over it. The pill already counts the message.
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

    /// How long each motion takes. Every one is critically damped, so the card never overshoots the pill.
    private enum Timing {
        /// Below to open, and away.
        static let slide: TimeInterval = 0.5
        /// Open to the pill, its corner or a laid-out card, and back.
        static let pill: TimeInterval = 0.5
    }

    /// The share of the way nearest the pill, or a laid-out card, over which the card thins out or comes up.
    private static let fadeShare = 0.38

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

    /// Puts `view` over the mail screens, under the dimming and the card: the place of the drafts laid out to pick
    /// from, so a picked one's card can grow over them.
    func place(_ view: UIView) {
        shelf.view.insertSubview(view, belowSubview: dimming)
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
            begin(opening(composer, from: rising, arrived: {}), following: nil)
        case .dock(let undocked):
            begin(opening(composer, from: outOfDock, arrived: undocked), following: nil)
        case .card(let frame, let radius, let undocked):
            let start = SystemAccessibility.reducesMotion ? rising : .clear(frame, cornerRadius: radius)
            begin(opening(composer, from: start, arrived: undocked), following: nil)
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

    /// Finishes the message's motion under way at once, at its end: a minimize ends minimized, an open ends open. A
    /// message that its landing opens moves on its own.
    func settleNow() {
        guard case .moving(let move) = motion else { return }
        move.animation.finishNow()
    }

    /// Finishes everything under way at once, a message that a landing opens too, as before the window changes size.
    func settleEverything() {
        while case .moving(let move) = motion {
            move.animation.finishNow()
            // Each motion lands as it finishes; one that didn't would otherwise be finished forever.
            if case .moving(let next) = motion, next.animation === move.animation { return }
        }
    }

    /// The shelf minimizes the message being written before it opens another, so the stage is empty by the time one
    /// opens. A message still on it would stay stuck under the new card: it is taken off.
    private func clearLeftover() {
        guard let leftover = composer else { return }
        assertionFailure("A message opened while another was still on the stage")
        if case .moving(let move) = motion {
            // Idle first, so the motion lands on nothing.
            motion = .idle
            move.animation.finishNow()
            // The pill counted a card that will never land in it.
            if case .leaving(.pill, _) = move.leg { dock.turnAway() }
        }
        clear(leftover)
    }

    /// Where an opening card starts.
    private enum Start {
        /// Opaque at `frame`, below the screen or by the pill's corner, taking `duration` to open.
        case solid(CGRect, cornerRadius: CGFloat, duration: TimeInterval)
        /// Clear at `frame`, on the pill or a laid-out card, coming up as it grows.
        case clear(CGRect, cornerRadius: CGFloat)
    }

    /// Below the screen, sliding up.
    private var rising: Start {
        .solid(below, cornerRadius: ComposerCardView.openCornerRadius, duration: Timing.slide)
    }

    /// Where a card opening out of the pill starts: below with Reduce Motion, on the pill on show, or by its corner.
    private var outOfDock: Start {
        if SystemAccessibility.reducesMotion { return rising }
        if let spot = dock.spot(in: shelf.view) { return .clear(spot.frame, cornerRadius: spot.frame.height / 2) }
        return .solid(corner, cornerRadius: corner.height / 2, duration: Timing.pill)
    }

    private func opening(_ composer: ComposeViewController, from start: Start, arrived: @escaping () -> Void)
        -> Move
    {
        let open = openFrame
        let grow = {
            self.card.fit(open, cornerRadius: ComposerCardView.openCornerRadius)
            self.dimming.alpha = 1
        }
        let animation: ScrubbedAnimation
        switch start {
        case .solid(let frame, let radius, let duration):
            card.fit(frame, cornerRadius: radius)
            animation = self.animation(distance: 0, heading: .up, duration: duration, animations: grow)
        case .clear(let frame, let radius):
            card.fit(frame, cornerRadius: radius)
            card.alpha = 0
            // Keyframes start from what was last committed to the screen: the hidden card wherever it last landed,
            // not this pose. Committing the pose first makes it the start.
            CATransaction.flush()
            animation = keyframes(distance: 0, heading: .up) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1, animations: grow)
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: Self.fadeShare) { self.card.alpha = 1 }
            }
        }
        return Move(composer: composer, leg: .opening(arrived: arrived), animation: animation)
    }

    /// The open card on its way to where `leaving` sends it. A card that keeps its size slides; one that shrinks
    /// turns into a capsule as it goes, and one headed for the pill thins out over it.
    private func leaving(_ composer: ComposeViewController, _ leaving: Leaving) -> Move {
        let landing = landing(for: leaving.destination)
        let target = landing.frame
        let distance = target.minY - card.frame.minY
        let slides = target.size == card.frame.size
        let shrink = {
            self.card.fit(target, cornerRadius: slides ? ComposerCardView.openCornerRadius : target.height / 2)
            self.dimming.alpha = 0
        }
        let animation =
            if case .pill = landing {
                keyframes(distance: distance, heading: .down) {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1, animations: shrink)
                    UIView.addKeyframe(withRelativeStartTime: 1 - Self.fadeShare, relativeDuration: Self.fadeShare) {
                        self.card.alpha = 0
                    }
                }
            } else {
                self.animation(
                    distance: distance, heading: .down, duration: slides ? Timing.slide : Timing.pill,
                    animations: shrink)
            }
        return Move(composer: composer, leg: .leaving(landing, landed: leaving.landed), animation: animation)
    }

    /// Where a card leaving for `destination` comes to rest, measured as it sets off. Heading for the pill starts its
    /// reception: the pill counts the message now, under the open card, so it is already right when the card thins
    /// out over it. `land` is where the reception ends, or `clearLeftover` when the card is taken off.
    private func landing(for destination: Destination) -> Landing {
        switch destination {
        case .away:
            return .away(below)
        case .dock(let docked):
            if SystemAccessibility.reducesMotion { return .offscreen(below, docked: docked) }
            guard let spot = dock.receive(in: shelf.view) else { return .offscreen(corner, docked: docked) }
            return .pill(spot, docked: docked)
        }
    }

    /// One animation whose shape and opacity are keyframes of it, so they share one curve whatever the finger or the
    /// spring does.
    private func keyframes(distance: CGFloat, heading: ScrubbedAnimation.Heading, keyframes: @escaping () -> Void)
        -> ScrubbedAnimation
    {
        animation(distance: distance, heading: heading, duration: Timing.pill) {
            UIView.animateKeyframes(withDuration: 0, delay: 0, options: [.calculationModeLinear], animations: keyframes)
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

    /// The card came to rest at its end, or back where it started: the one place a motion ends.
    private func land(arrived: Bool) {
        guard case .moving(let move) = motion else { return }
        let composer = move.composer
        switch move.leg {
        case .opening(let arrived):
            // Nothing follows a finger onto the screen, so an opening always arrives. The pill lets the message go
            // under the open card.
            rest(composer)
            arrived()
            composer.didOpen()
        case .leaving(let landing, let landed):
            guard arrived else {
                // Back at full size, over the pill, which stops counting the message.
                if case .pill = landing { dock.turnAway() }
                rest(composer)
                return landed(false)
            }
            clear(composer)
            switch landing {
            case .pill(let spot, let docked):
                dock.land(docked)
                spot.pill.bounce()
            case .offscreen(_, let docked):
                docked()
            case .away:
                break
            }
            // May open another message.
            landed(true)
        }
    }

    /// The composer fills the card, at rest.
    private func rest(_ composer: ComposeViewController) {
        motion = .open(composer)
        card.alpha = 1
        dimming.alpha = 1
        layout()
    }

    /// Nothing on the screen: the card and the dimming hidden, the composer taken out of the card.
    private func clear(_ composer: ComposeViewController) {
        motion = .idle
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
    var corner: CGRect {
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
