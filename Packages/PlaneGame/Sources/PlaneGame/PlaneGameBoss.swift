public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A boss: it slides in under the ceiling, moves and attacks until its hits run out, then comes apart. Its status
/// moves on only through `strike(_:)` and `advance(by:towardX:on:attacking:)`.
public struct PlaneGameBoss: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Junk Mail, the spam envelope in a crown, which drops spam.
        case junk
        /// The Phisher, the at sign with a line and hook, which casts lures.
        case phisher
    }

    public enum Status: Equatable, Sendable {
        /// Sliding in from above the top edge. Nothing hits it.
        case arriving(elapsed: TimeInterval)
        /// Moving and attacking. `sinceAttack` counts up to the next one.
        case fighting(sinceAttack: TimeInterval)
        /// Beaten and coming apart.
        case falling(elapsed: TimeInterval)
    }

    public let kind: Kind
    /// 1 for the first boss of a game.
    public let number: Int
    public var position: CGPoint
    public let hits: Int
    public var hitsLeft: Int
    public var status: Status
    /// Seconds since it started to slide in, which Junk Mail's glide is timed from.
    var age: TimeInterval = 0

    /// Boss `number` of a game, above the top edge of `field` and about to slide in. They take turns, Junk Mail
    /// first, and each takes more hits than the last.
    public init(number: Int, on field: PlaneGameField) {
        kind = number.isMultiple(of: 2) ? .phisher : .junk
        self.number = number
        hits = min(
            PlaneGameRules.bossFirstHits + PlaneGameRules.bossMoreHits * (number - 1), PlaneGameRules.bossMostHits)
        hitsLeft = hits
        status = .arriving(elapsed: 0)
        position = .zero
        place(on: field)
    }

    /// Points for beating it.
    public var points: Int {
        PlaneGameRules.bossPoints * number
    }

    /// How close a shot has to come to strike it.
    public var radius: CGFloat {
        switch kind {
        case .junk: 44
        case .phisher: 40
        }
    }

    /// Down to half its hits or fewer, when it attacks harder.
    public var isAngry: Bool {
        hitsLeft * 2 <= hits
    }

    /// Fighting, the only time a shot can strike it.
    var canBeHit: Bool {
        if case .fighting = status { true } else { false }
    }

    /// Coming apart for long enough that it is gone.
    var isGone: Bool {
        if case .falling(let elapsed) = status { elapsed >= PlaneGameRules.bossFall } else { false }
    }

    /// Takes `count` hits off it while it fights. The last one starts its fall, and then this is true.
    mutating func strike(_ count: Int) -> Bool {
        guard canBeHit else { return false }
        hitsLeft = max(hitsLeft - count, 0)
        guard hitsLeft == 0 else { return false }
        status = .falling(elapsed: 0)
        return true
    }

    /// Whether a circle of `radius` at `point` overlaps it.
    func touches(_ point: CGPoint, within radius: CGFloat) -> Bool {
        let reach = self.radius + radius
        let dx = position.x - point.x
        let dy = position.y - point.y
        return dx * dx + dy * dy <= reach * reach
    }
}
