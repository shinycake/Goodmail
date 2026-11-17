import CoreGraphics
import Foundation

/// A doodle stage at one instant: where everything that moves is. It is a function of the stage's size, the
/// touches that have landed on it and the time, so a frame is drawn by asking, not by stepping anything forward.
nonisolated struct DoodleScene: Equatable, Sendable {
    /// Whether the stage moves.
    enum Clock: Equatable, Sendable {
        /// Reduce Motion is on: everything rests in its place and touches set nothing off.
        case stopped
        case running(Date)
    }

    let size: CGSize
    let pokes: [DoodlePoke]
    let clock: Clock
    /// Mirrors the doodles and sends the planes off to the left.
    let rightToLeft: Bool
    /// Where the envelopes sit, which pokes are placed from: the middle of the stage unless given.
    var focus: CGPoint? = nil
    /// How much of the idle motion plays, from 0, every doodle resting in its place, to 1. Touches aren't idle
    /// motion, so they play in full.
    var energy: Double = 1
    /// How often a plane crosses the stage by itself.
    var passInterval: TimeInterval = DoodleScene.passEvery
    /// No plane sets off by itself from now on, so the stage can come to rest with nothing in the air.
    var quietFrom: Date = .distantFuture

    /// The doodles keep within this width around the envelopes on a wide screen, so they don't thin out to nothing.
    static let widestField: CGFloat = 600

    /// A plane crosses the stage by itself this often unless told otherwise, so the screen never sits quite still.
    static let passEvery: TimeInterval = 14
    static let passTime: TimeInterval = 3.2

    var center: CGPoint { focus ?? CGPoint(x: size.width / 2, y: size.height / 2) }

    /// How wide the envelopes are fanned: 1 as in the icon. They breathe a little at rest and swing open on a poke.
    var fan: Double {
        guard case .running(let now) = clock else { return 1 }
        return 1 + 0.04 * energy * sin(now.timeIntervalSinceReferenceDate * 0.7) + 0.45 * hop(at: now)
    }

    /// How far the envelopes have risen from their place: bobbing at rest, hopping on a poke.
    var lift: CGFloat {
        guard case .running(let now) = clock else { return 0 }
        return 3 * energy * sin(now.timeIntervalSinceReferenceDate * 0.9) + 9 * hop(at: now)
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
            x: rest.x + 4 * energy * sin(seconds * 0.35 + phase) + pushed.width,
            y: rest.y + 5 * energy * cos(seconds * 0.3 + phase) + pushed.height)
    }

    /// How far a doodle has turned from the angle it rests at, in degrees.
    func sway(phase: Double) -> Double {
        guard case .running(let now) = clock else { return 0 }
        return 7 * energy * sin(now.timeIntervalSinceReferenceDate * 0.25 + phase)
    }

    /// The paper planes in the air: one from each poke, and the one that passes by itself.
    var flights: [PlaneFlight] {
        guard case .running(let now) = clock else { return [] }
        let seconds = now.timeIntervalSinceReferenceDate
        let pass = (seconds / passInterval).rounded(.down)
        let setOff = pass * passInterval
        // It comes in low from beyond the leading edge.
        let entry = CGPoint(x: rightToLeft ? size.width + 30 : -30, y: size.height * 0.8)
        let passing =
            setOff < quietFrom.timeIntervalSinceReferenceDate
            ? PlaneCourse(origin: entry, size: size, rightToLeft: rightToLeft)
                .flight(at: (seconds - setOff) / Self.passTime, number: Int(pass))
            : nil
        return touches(at: now).compactMap { $0.flight(in: size, rightToLeft: rightToLeft) }
            + [passing].compactMap(\.self)
    }

    private func touches(at now: Date) -> [DoodleTouch] {
        pokes.map { poke in
            DoodleTouch(
                origin: CGPoint(x: center.x + poke.offset.width, y: center.y + poke.offset.height),
                elapsed: now.timeIntervalSince(poke.time), number: poke.number)
        }
    }

    private func hop(at now: Date) -> Double {
        touches(at: now).reduce(0) { $0 + $1.hop(around: center) }
    }
}
