import MailCore
import UIKit

/// An animation a finger can drive: it follows a drag until let go, then a spring that picks up the finger's speed
/// takes it to whichever end the motion leads. Without a drag it just runs.
final class ScrubbedAnimation: NSObject {
    /// Which way the motion runs on the screen, so the finger's travel counts toward it.
    enum Heading {
        case down
        case up
    }

    private enum Phase {
        /// Made, not yet run.
        case ready
        /// The finger dragging `pan` is down but hasn't moved. The motion starts with its first movement, after what
        /// the touch itself set off (the keyboard going away, the picker coming up) has had its turn.
        case holding(UIPanGestureRecognizer)
        /// Scrubbed by the finger dragging `pan`, which last moved at `moved` (in `CACurrentMediaTime`).
        case following(UIPanGestureRecognizer, moved: CFTimeInterval)
        /// A spring takes it the rest of the way.
        case settling
    }

    private let animator: UIViewPropertyAnimator
    private let landed: (Bool) -> Void
    /// Watches the spring come to rest, as an animator paused at its ends doesn't finish by itself.
    private var running: NSKeyValueObservation?
    private let drag: CardDrag
    private let heading: Heading
    /// The view the finger's travel is measured in.
    private unowned let space: UIView
    private var phase = Phase.ready

    /// `animations` run over `distance` points heading `heading`; `landed` hears `true` at their end, `false` back where
    /// they started.
    init(
        distance: CGFloat, heading: Heading, in space: UIView, duration: TimeInterval = 0.5,
        animations: @escaping () -> Void, landed: @escaping (Bool) -> Void
    ) {
        animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 1, animations: animations)
        drag = CardDrag(distance: Double(abs(distance)))
        self.heading = heading
        self.space = space
        self.landed = landed
        super.init()
        // Left to finish on its own, an animator the finger is holding can run out from under it when the main
        // thread stalls. Paused at its ends instead, it waits for `settled` to end it once the spring has stopped.
        animator.pausesOnCompletion = true
        animator.addCompletion { position in landed(position == .end) }
        running = animator.observe(\.isRunning) { [weak self] animator, _ in
            // KVO calls back on the thread that changed the animator, and only the main thread drives it.
            MainActor.assumeIsolated {
                guard let self, !animator.isRunning else { return }
                self.settled()
            }
        }
    }

    /// Starts the motion, under the finger dragging `pan` if there is one.
    func run(following pan: UIPanGestureRecognizer?) {
        guard case .ready = phase else { return }
        guard let pan else {
            phase = .settling
            return animator.startAnimation()
        }
        phase = .holding(pan)
        pan.setTranslation(.zero, in: space)
        pan.addTarget(self, action: #selector(followed(_:)))
    }

    /// Ends the motion at once, where it was headed.
    func finishNow() {
        switch phase {
        case .holding(let pan):
            pan.removeTarget(self, action: #selector(followed(_:)))
            animator.pauseAnimation()
        case .following(let pan, _):
            pan.removeTarget(self, action: #selector(followed(_:)))
        case .ready, .settling:
            break
        }
        phase = .settling
        end()
    }

    @objc private func followed(_ pan: UIPanGestureRecognizer) {
        switch phase {
        case .holding(let holding) where holding === pan:
            held(pan)
        case .following(let following, let moved) where following === pan:
            follow(pan, moved: moved)
        case .ready, .holding, .following, .settling:
            break
        }
    }

    /// The finger is down, the motion not yet started: its first movement or its release starts it.
    private func held(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .changed, .ended:
            // A quick swipe can end without a movement before it, and its speed still counts.
            animator.pauseAnimation()
            animator.fractionComplete = drag.progress(translation: toward(pan.translation(in: space).y))
            phase = .following(pan, moved: CACurrentMediaTime())
            follow(pan, moved: CACurrentMediaTime())
        case .cancelled, .failed:
            // Called off before it moved: nothing started, so it's where it began.
            pan.removeTarget(self, action: #selector(followed(_:)))
            phase = .settling
            landed(false)
        case .possible, .began, .recognized:
            break
        @unknown default:
            break
        }
    }

    private func follow(_ pan: UIPanGestureRecognizer, moved: CFTimeInterval) {
        switch pan.state {
        case .changed:
            animator.fractionComplete = drag.progress(translation: toward(pan.translation(in: space).y))
            phase = .following(pan, moved: CACurrentMediaTime())
        case .ended:
            let release = CardDrag.releaseVelocity(speed(pan), stillFor: CACurrentMediaTime() - moved)
            settle(CardDrag.settle(progress: animator.fractionComplete, velocity: release), speed: release, pan)
        case .cancelled, .failed:
            settle(.goBack, speed: 0, pan)
        case .possible, .began, .recognized:
            break
        @unknown default:
            break
        }
    }

    /// Points along the motion's heading.
    private func toward(_ points: CGFloat) -> Double {
        Double(heading == .down ? points : -points)
    }

    /// The finger's speed along the motion, in trips a second.
    private func speed(_ pan: UIPanGestureRecognizer) -> Double {
        drag.velocity(points: toward(pan.velocity(in: space).y))
    }

    /// A spring that came to rest ends the motion where it stopped. One the finger holds keeps it.
    private func settled() {
        guard case .settling = phase, animator.state == .active else { return }
        end()
    }

    /// Stops the animator where it's headed. Stopping forgets which way it ran, so that's read first.
    private func end() {
        let position: UIViewAnimatingPosition = animator.isReversed ? .start : .end
        animator.stopAnimation(false)
        animator.finishAnimation(at: position)
    }

    /// Hands the motion to a spring toward `target` that picks up the finger's `speed` in trips a second.
    private func settle(_ target: CardDrag.Settle, speed: Double, _ pan: UIPanGestureRecognizer) {
        pan.removeTarget(self, action: #selector(followed(_:)))
        phase = .settling
        let progress = Double(animator.fractionComplete)
        let push = CardDrag.springVelocity(progress: progress, velocity: speed, settle: target)
        animator.isReversed = target == .goBack
        animator.continueAnimation(
            withTimingParameters: UISpringTimingParameters(
                dampingRatio: 1, initialVelocity: CGVector(dx: push, dy: push)),
            durationFactor: CardDrag.durationFactor(progress: progress, settle: target))
    }
}
