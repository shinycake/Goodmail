/// The arithmetic of dragging the composer between the screen and the bar: how far along the finger has taken it, and
/// where it settles once let go. Progress runs from 0 where the drag started to 1 where it leads, and velocity is in
/// whole trips a second.
public struct CardDrag: Sendable, Equatable {
    /// How far the card travels, in points, from where the drag starts to where it leads.
    public let distance: Double

    public init(distance: Double) {
        self.distance = distance
    }

    /// Where the card is after the finger moved `translation` points toward where the drag leads. It stops at either
    /// end.
    public func progress(translation: Double) -> Double {
        guard distance > 0 else { return 1 }
        return min(max(translation / distance, 0), 1)
    }

    /// The finger's speed toward where the drag leads, from points a second.
    public func velocity(points: Double) -> Double {
        distance > 0 ? points / distance : 0
    }

    public enum Settle: Sendable, Equatable {
        /// On to where the drag leads.
        case arrive
        /// Back to where it started.
        case goBack
    }

    /// The finger's speed as it lets go, `velocity` as last measured `stillFor` seconds before. A pan keeps reporting
    /// the last speed it saw while the finger rests, so a finger that stopped before lifting lets go without speed.
    public static func releaseVelocity(_ velocity: Double, stillFor: Double) -> Double {
        stillFor >= stillness ? 0 : velocity
    }

    /// Where a card let go at `progress`, moving at `velocity`, comes to rest: a flick carries it, and otherwise it
    /// goes to the nearer end from where it would coast to, decelerating as a scroll view does, as sheets do.
    public static func settle(progress: Double, velocity: Double) -> Settle {
        if abs(velocity) >= flick { return velocity > 0 ? .arrive : .goBack }
        return progress + velocity * coasting >= 0.5 ? .arrive : .goBack
    }

    /// The spring's starting speed as it takes over from the finger, in remaining distances a second, as
    /// `UISpringTimingParameters` wants it. A finger moving the other way gives it no push.
    public static func springVelocity(progress: Double, velocity: Double, settle: Settle) -> Double {
        let remaining = remaining(progress: progress, settle: settle)
        let toward = settle == .arrive ? velocity : -velocity
        guard remaining > 0, toward > 0 else { return 0 }
        return min(toward / remaining, maximumSpringVelocity)
    }

    /// The share of the full motion's time the spring takes for the rest of the way: less the less is left, so a card
    /// let go where it's going lands at once, but never so little that it snaps.
    public static func durationFactor(progress: Double, settle: Settle) -> Double {
        max(remaining(progress: progress, settle: settle), shortestSettle)
    }

    private static func remaining(progress: Double, settle: Settle) -> Double {
        settle == .arrive ? 1 - progress : progress
    }

    /// Seconds without movement after which a finger counts as having stopped.
    public static let stillness = 0.1
    /// Beyond this, a nearly finished drag would snap.
    public static let maximumSpringVelocity = 20.0
    /// The least share of the motion's time a settle takes.
    private static let shortestSettle = 0.3
    /// Trips a second that count as a flick.
    private static let flick = 1.5
    /// How far a let-go card coasts for each trip a second it moves: a scroll view's normal deceleration rate `r`
    /// carries a velocity `v` points a millisecond `v · r / (1 − r)` points, about half a second of motion.
    private static let coasting = deceleration / (1 - deceleration) / 1000
    /// `UIScrollView.DecelerationRate.normal`.
    private static let deceleration = 0.998
}
