import CoreGraphics
import Foundation

/// A touch on a doodle stage. What it sets off (the doodles it pushes aside, the hop it gives the
/// envelopes, the paper plane it sends) is worked out from how long ago it landed, so nothing is stepped forward or
/// cleaned up while it plays.
nonisolated struct DoodlePoke: Equatable, Sendable {
    /// Where it landed, from the middle of the stage, so it keeps its place by the envelopes when the stage changes
    /// size.
    let offset: CGSize
    let time: Date
    /// Counts the pokes, so each one's plane takes the next of the icon's colors.
    let number: Int

    /// Everything a poke sets off has settled or left the stage by now.
    static let lifetime: TimeInterval = 3
    /// How long its plane takes to fly off the stage.
    static let flightTime: TimeInterval = 2.4
}

/// A poke as it plays out at one instant: where on the stage it landed, and how long ago.
nonisolated struct DoodleTouch: Equatable, Sendable {
    let origin: CGPoint
    let elapsed: TimeInterval
    let number: Int

    /// How far it has pushed something at `point`: away from the touch, hardest on what is nearest, and a moment
    /// later the farther away it is, the way a ripple spreads.
    func push(on point: CGPoint) -> CGSize {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let distance = max(hypot(dx, dy), 1)
        let reach = 22 * exp(-distance / 160)
        let swing = DoodleSpring.swing(elapsed - distance / 800)
        return CGSize(width: dx / distance * reach * swing, height: dy / distance * reach * swing)
    }

    /// The hop it gives the envelopes around `center`: a full one for a touch on them, a nod for one far away.
    func hop(around center: CGPoint) -> Double {
        let distance = hypot(center.x - origin.x, center.y - origin.y)
        return (0.3 + 0.7 * exp(-distance / 120)) * DoodleSpring.swing(elapsed)
    }

    /// Its paper plane, while it is in the air.
    func flight(in size: CGSize, rightToLeft: Bool) -> PlaneFlight? {
        PlaneCourse(origin: origin, size: size, rightToLeft: rightToLeft)
            .flight(at: elapsed / DoodlePoke.flightTime, number: number)
    }
}

/// The touches still playing out on the stage.
nonisolated struct DoodlePokes: Equatable, Sendable {
    private(set) var live: [DoodlePoke] = []
    private var landed = 0

    /// A flurry of taps keeps only its last few, so the stage stays cheap to draw.
    static let limit = 4

    /// Adds a touch, and drops the ones that have played out.
    mutating func land(offset: CGSize, time: Date) {
        live.removeAll { time.timeIntervalSince($0.time) > DoodlePoke.lifetime }
        live = live.suffix(Self.limit - 1) + [DoodlePoke(offset: offset, time: time, number: landed)]
        landed += 1
    }
}

/// The spring in everything a touch sets off.
nonisolated enum DoodleSpring {
    /// A plucked spring's swing `elapsed` seconds after the pluck: from rest out to about 1, back past rest, and
    /// still again within a second and a half. Nothing has moved before the pluck.
    static func swing(_ elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        return 1.75 * exp(-4.5 * elapsed) * sin(11 * elapsed)
    }
}
