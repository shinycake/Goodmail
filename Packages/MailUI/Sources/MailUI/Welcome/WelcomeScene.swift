import CoreGraphics
import Foundation

/// A touch on the welcome screen's stage. What it sets off (the doodles it pushes aside, the hop it gives the
/// envelopes, the paper plane it sends) is worked out from how long ago it landed, so nothing is stepped forward or
/// cleaned up while it plays.
nonisolated struct WelcomePoke: Equatable, Sendable {
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
nonisolated struct WelcomeTouch: Equatable, Sendable {
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
        let swing = WelcomeSpring.swing(elapsed - distance / 800)
        return CGSize(width: dx / distance * reach * swing, height: dy / distance * reach * swing)
    }

    /// The hop it gives the envelopes around `center`: a full one for a touch on them, a nod for one far away.
    func hop(around center: CGPoint) -> Double {
        let distance = hypot(center.x - origin.x, center.y - origin.y)
        return (0.3 + 0.7 * exp(-distance / 120)) * WelcomeSpring.swing(elapsed)
    }

    /// Its paper plane, while it is in the air.
    func flight(in size: CGSize, rightToLeft: Bool) -> WelcomeFlight? {
        WelcomeCourse(origin: origin, size: size, rightToLeft: rightToLeft)
            .flight(at: elapsed / WelcomePoke.flightTime, number: number)
    }
}

/// The touches still playing out on the stage.
nonisolated struct WelcomePokes: Equatable, Sendable {
    private(set) var live: [WelcomePoke] = []
    private var landed = 0

    /// A flurry of taps keeps only its last few, so the stage stays cheap to draw.
    static let limit = 4

    /// Adds a touch, and drops the ones that have played out.
    mutating func land(offset: CGSize, time: Date) {
        live.removeAll { time.timeIntervalSince($0.time) > WelcomePoke.lifetime }
        live = live.suffix(Self.limit - 1) + [WelcomePoke(offset: offset, time: time, number: landed)]
        landed += 1
    }
}

/// The spring in everything a touch sets off.
nonisolated enum WelcomeSpring {
    /// A plucked spring's swing `elapsed` seconds after the pluck: from rest out to about 1, back past rest, and
    /// still again within a second and a half. Nothing has moved before the pluck.
    static func swing(_ elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        return 1.75 * exp(-4.5 * elapsed) * sin(11 * elapsed)
    }
}

/// The path a paper plane flies: off toward the trailing edge of the stage, climbing, with a loop on the way.
nonisolated struct WelcomeCourse: Sendable {
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
    func flight(at progress: Double, number: Int) -> WelcomeFlight? {
        guard (0...1).contains(progress) else { return nil }
        let position = point(at: progress)
        let ahead = point(at: progress + 0.01)
        return WelcomeFlight(
            position: position,
            heading: atan2(ahead.y - position.y, ahead.x - position.x),
            trail: (0...WelcomeFlight.trailSteps).map { point(at: max(progress - Double($0) * 0.02, 0)) },
            opacity: min(1, progress / 0.08, (1 - progress) / 0.12),
            number: number)
    }
}

/// A paper plane in the air.
nonisolated struct WelcomeFlight: Equatable, Sendable {
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

/// The welcome stage at one instant: where everything that moves is. It is a function of the stage's size, the
/// touches that have landed on it and the time, so a frame is drawn by asking, not by stepping anything forward.
nonisolated struct WelcomeScene: Equatable, Sendable {
    /// Whether the stage moves.
    enum Clock: Equatable, Sendable {
        /// Reduce Motion is on: everything rests in its place and touches set nothing off.
        case stopped
        case running(Date)
    }

    let size: CGSize
    let pokes: [WelcomePoke]
    let clock: Clock
    /// Mirrors the doodles and sends the planes off to the left.
    let rightToLeft: Bool

    /// The doodles keep within this width around the envelopes on a wide screen, so they don't thin out to nothing.
    static let widestField: CGFloat = 600

    /// A plane crosses the stage by itself this often, so the screen never sits quite still.
    static let passEvery: TimeInterval = 14
    static let passTime: TimeInterval = 3.2

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    /// How wide the envelopes are fanned: 1 as in the icon. They breathe a little at rest and swing open on a poke.
    var fan: Double {
        guard case .running(let now) = clock else { return 1 }
        return 1 + 0.04 * sin(now.timeIntervalSinceReferenceDate * 0.7) + 0.45 * hop(at: now)
    }

    /// How far the envelopes have risen from their place: bobbing at rest, hopping on a poke.
    var lift: CGFloat {
        guard case .running(let now) = clock else { return 0 }
        return 3 * sin(now.timeIntervalSinceReferenceDate * 0.9) + 9 * hop(at: now)
    }

    /// Where a doodle is: `anchor` gives its place as fractions of the field's width and height, and `phase` sets
    /// its drift apart from its neighbors'.
    func position(anchor: CGPoint, phase: Double) -> CGPoint {
        let field = min(size.width, Self.widestField)
        let across = rightToLeft ? 1 - anchor.x : anchor.x
        let rest = CGPoint(x: (size.width - field) / 2 + field * across, y: size.height * anchor.y)
        guard case .running(let now) = clock else { return rest }
        let seconds = now.timeIntervalSinceReferenceDate
        let pushed = touches(at: now).reduce(CGSize.zero) { sum, touch in
            let push = touch.push(on: rest)
            return CGSize(width: sum.width + push.width, height: sum.height + push.height)
        }
        return CGPoint(
            x: rest.x + 4 * sin(seconds * 0.35 + phase) + pushed.width,
            y: rest.y + 5 * cos(seconds * 0.3 + phase) + pushed.height)
    }

    /// How far a doodle has turned from the angle it rests at, in degrees.
    func sway(phase: Double) -> Double {
        guard case .running(let now) = clock else { return 0 }
        return 7 * sin(now.timeIntervalSinceReferenceDate * 0.25 + phase)
    }

    /// The paper planes in the air: one from each poke, and the one that passes by itself.
    var flights: [WelcomeFlight] {
        guard case .running(let now) = clock else { return [] }
        let seconds = now.timeIntervalSinceReferenceDate
        let pass = (seconds / Self.passEvery).rounded(.down)
        // It comes in low from beyond the leading edge.
        let entry = CGPoint(x: rightToLeft ? size.width + 30 : -30, y: size.height * 0.8)
        let passing = WelcomeCourse(origin: entry, size: size, rightToLeft: rightToLeft)
            .flight(at: (seconds - pass * Self.passEvery) / Self.passTime, number: Int(pass))
        return touches(at: now).compactMap { $0.flight(in: size, rightToLeft: rightToLeft) }
            + [passing].compactMap(\.self)
    }

    private func touches(at now: Date) -> [WelcomeTouch] {
        pokes.map { poke in
            WelcomeTouch(
                origin: CGPoint(x: center.x + poke.offset.width, y: center.y + poke.offset.height),
                elapsed: now.timeIntervalSince(poke.time), number: poke.number)
        }
    }

    private func hop(at now: Date) -> Double {
        touches(at: now).reduce(0) { $0 + $1.hop(around: center) }
    }
}

/// How the envelopes lean under a finger dragging them by `pull`.
nonisolated struct WelcomeLean: Equatable, Sendable {
    /// How far they follow the finger: half the way at first and then less and less, as if held on elastic.
    let shift: CGSize

    /// The farthest they can be pulled from their place, each way.
    static let reach: CGFloat = 50

    init(pull: CGSize) {
        shift = CGSize(
            width: Self.reach * tanh(pull.width / (2 * Self.reach)),
            height: Self.reach * tanh(pull.height / (2 * Self.reach)))
    }

    /// How far they tip over as they are dragged up or down, in degrees about the horizontal.
    var pitch: Double { -shift.height / Self.reach * 22 }
    /// How far they tip over as they are dragged sideways, in degrees about the vertical.
    var yaw: Double { shift.width / Self.reach * 22 }
    /// The fan opens as they are pulled, by up to half as much again.
    var spread: Double { min(hypot(shift.width, shift.height) / Self.reach, 1) * 0.5 }
}
