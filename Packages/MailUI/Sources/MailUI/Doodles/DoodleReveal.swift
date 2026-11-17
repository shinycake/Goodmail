import CoreGraphics
import Foundation

/// The doodles drawing themselves in, nearest the envelopes first, the way a pen would sketch them around the pile.
/// Each one's progress is a function of the time since the drawing began, so a frame is drawn by asking.
nonisolated struct DoodleReveal: Equatable, Sendable {
    /// Where the drawing spreads out from.
    let origin: CGPoint
    /// The distance from `origin` at which a doodle starts last.
    let reach: CGFloat
    /// How long ago the nearest doodle started; negative before then.
    let elapsed: TimeInterval

    /// The farthest doodle starts this long after the nearest.
    static let spread: TimeInterval = 0.35
    /// How long one doodle takes to draw.
    static let duration: TimeInterval = 0.5
    /// Every doodle has drawn itself this long after the first started.
    static let total = spread + duration

    /// How much of the doodle at `point` is drawn, from 0 to 1, easing out as the pen lifts.
    func progress(at point: CGPoint) -> Double {
        let distance = hypot(point.x - origin.x, point.y - origin.y)
        let delay = Self.spread * min(distance / max(reach, 1), 1)
        let drawn = min(max((elapsed - delay) / Self.duration, 0), 1)
        return 1 - pow(1 - drawn, 3)
    }
}
