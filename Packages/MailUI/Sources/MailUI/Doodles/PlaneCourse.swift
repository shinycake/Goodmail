import CoreGraphics
import Foundation

/// The path a paper plane flies: off toward the trailing edge of the stage, climbing, with a loop on the way.
nonisolated struct PlaneCourse: Sendable {
    let origin: CGPoint
    /// How far it travels sideways, to just past the edge it leaves by. Negative flies left.
    let run: CGFloat
    /// How far it climbs. Less from near the top, so it leaves by the side and not through the status bar.
    let climb: CGFloat

    static let loopRadius: CGFloat = 30

    init(origin: CGPoint, size: CGSize, rightToLeft: Bool) {
        self.origin = origin
        run = rightToLeft ? -max(origin.x + 40, 120) : max(size.width - origin.x + 40, 120)
        climb = origin.y * 0.4
    }

    /// Where the plane is, `progress` of the way through its flight.
    func point(at progress: Double) -> CGPoint {
        // It sets off gently and gathers speed.
        let forward = 0.2 * progress + 0.8 * progress * progress
        let loop = min(max((progress - 0.2) / 0.5, 0), 1)
        let turn = 2 * Double.pi * loop * loop * (3 - 2 * loop)
        return CGPoint(
            x: origin.x + run * forward + (run < 0 ? -1 : 1) * Self.loopRadius * sin(turn),
            y: origin.y - climb * progress - Self.loopRadius * (1 - cos(turn)))
    }

    /// The plane `progress` of the way through its flight, or `nil` before it takes off and once it has left.
    func flight(at progress: Double, number: Int) -> PlaneFlight? {
        guard (0...1).contains(progress) else { return nil }
        let position = point(at: progress)
        let ahead = point(at: progress + 0.01)
        return PlaneFlight(
            position: position,
            heading: atan2(ahead.y - position.y, ahead.x - position.x),
            trail: (0...PlaneFlight.trailSteps).map { point(at: max(progress - Double($0) * 0.02, 0)) },
            opacity: min(1, progress / 0.08, (1 - progress) / 0.12),
            number: number)
    }
}

/// A paper plane in the air.
nonisolated struct PlaneFlight: Equatable, Sendable {
    let position: CGPoint
    /// The way it points, in radians clockwise from pointing right.
    let heading: Double
    /// The path just behind it, nearest first.
    let trail: [CGPoint]
    /// It fades in as it takes off and out as it leaves.
    let opacity: Double
    let number: Int

    static let trailSteps = 14
}
