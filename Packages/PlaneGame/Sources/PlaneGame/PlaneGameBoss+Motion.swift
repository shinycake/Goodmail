import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// How a boss moves and attacks: it slides in, then Junk Mail glides across the lanes dropping spam and the Phisher
/// keeps to one side of the plane casting lures. What it sends falls at the field's pace like everything else.
extension PlaneGameBoss {
    /// Something a boss sends at the plane.
    struct Sent: Equatable, Sendable {
        let kind: PlaneGameThing.Kind
        let position: CGPoint
        /// Its sideways speed, in points a second.
        let drift: CGFloat
    }

    /// Moves it on by `dt` on `field`, with the plane at `planeX`, and says what it sent. It attacks only while
    /// `attacking`.
    mutating func advance(by dt: TimeInterval, towardX planeX: CGFloat, on field: PlaneGameField, attacking: Bool)
        -> [Sent]
    {
        age += dt
        var sent: [Sent] = []
        switch status {
        case .arriving(let elapsed):
            let now = elapsed + dt
            status = now >= PlaneGameRules.bossArrival ? .fighting(sinceAttack: 0) : .arriving(elapsed: now)
        case .fighting(let sinceAttack):
            if kind == .phisher, sinceAttack >= PlaneGameRules.phisherHold {
                let reach = PlaneGameRules.phisherCreep * dt
                let aim = phisherAim(besideX: planeX, within: field.lanes(inset: radius))
                position.x += min(max(aim - position.x, -reach), reach)
            }
            var since = sinceAttack + dt
            if since >= attackEvery {
                since -= attackEvery
                if attacking { sent = attack(on: field) }
            }
            status = .fighting(sinceAttack: since)
        case .falling(let elapsed):
            status = .falling(elapsed: elapsed + dt)
        }
        place(on: field)
        return sent
    }

    /// Puts it where its status says on `field`: sliding down to hover under the ceiling, then there, inside the
    /// lanes by its radius. A resize comes through here too.
    mutating func place(on field: PlaneGameField) {
        let hover = field.ceiling + radius
        let lanes = field.lanes(inset: radius)
        let middle = (lanes.lowerBound + lanes.upperBound) / 2
        switch status {
        case .arriving(let elapsed):
            let start = -radius
            let eased = 1 - pow(1 - min(max(elapsed / PlaneGameRules.bossArrival, 0), 1), 3)
            position = CGPoint(x: middle, y: start + (hover - start) * CGFloat(eased))
        case .fighting:
            if kind == .junk {
                let glide = sin(2 * .pi * (age - PlaneGameRules.bossArrival) / PlaneGameRules.junkGlidePeriod)
                position.x = middle + min(lanes.upperBound - middle, PlaneGameRules.junkGlideReach) * CGFloat(glide)
            }
            position.y = hover
        case .falling:
            position.y = hover
        }
        position.x = lanes.clamping(position.x)
    }

    /// Where the Phisher creeps to: `phisherOffset` from the plane on the side it is on now, or on the other side when
    /// a wall leaves no room there, so it crosses over the plane, which is the plane's chance to hit it. In lanes too
    /// narrow for either, it settles at the end farther from the plane rather than flipping between them.
    private func phisherAim(besideX planeX: CGFloat, within lanes: ClosedRange<CGFloat>) -> CGFloat {
        let side: CGFloat = position.x < planeX ? -1 : 1
        let near = planeX + side * PlaneGameRules.phisherOffset
        let far = planeX - side * PlaneGameRules.phisherOffset
        if lanes.contains(near) { return near }
        if lanes.contains(far) { return far }
        return planeX - lanes.lowerBound > lanes.upperBound - planeX ? lanes.lowerBound : lanes.upperBound
    }

    /// The time between attacks, shorter once it is angry.
    private var attackEvery: TimeInterval {
        switch kind {
        case .junk: isAngry ? PlaneGameRules.junkAngryDropEvery : PlaneGameRules.junkDropEvery
        case .phisher: isAngry ? PlaneGameRules.phisherAngryCastEvery : PlaneGameRules.phisherCastEvery
        }
    }

    /// One attack from just under it: a spam, or two side by side, or a fan of lures.
    private func attack(on field: PlaneGameField) -> [Sent] {
        let y = position.y + radius
        switch kind {
        case .junk:
            let lanes = field.lanes(inset: PlaneGameThing.Kind.spam.radius + PlaneGameThing.Kind.spam.swing)
            let offsets = isAngry ? [-PlaneGameRules.junkPairSpacing / 2, PlaneGameRules.junkPairSpacing / 2] : [0]
            return offsets.map {
                Sent(kind: .spam, position: CGPoint(x: lanes.clamping(position.x + $0), y: y), drift: 0)
            }
        case .phisher:
            let count = isAngry ? PlaneGameRules.phisherAngryLures : PlaneGameRules.phisherLures
            let spread = PlaneGameRules.lureSpread * field.pace
            return (0..<count).map { index in
                let share = CGFloat(index) / CGFloat(count - 1) * 2 - 1
                return Sent(kind: .lure, position: CGPoint(x: position.x, y: y), drift: share * spread)
            }
        }
    }
}
