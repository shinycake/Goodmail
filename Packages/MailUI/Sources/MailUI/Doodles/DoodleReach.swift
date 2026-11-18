import CoreGraphics
import Foundation

/// How far touches together move something: as far as they add up to while that is no more than one touch
/// can do, then leveling off smoothly toward `most`, so a flurry of taps doesn't throw anything about.
nonisolated struct DoodleReach: Equatable, Sendable {
    let one: Double
    let most: Double

    func ease(_ value: Double) -> Double {
        let size = abs(value)
        guard size > one else { return value }
        let eased = one + (most - one) * tanh((size - one) / (most - one))
        return value < 0 ? -eased : eased
    }

    func ease(_ push: CGSize) -> CGSize {
        let length = hypot(push.width, push.height)
        guard length > one else { return push }
        let scale = ease(length) / length
        return CGSize(width: push.width * scale, height: push.height * scale)
    }
}
