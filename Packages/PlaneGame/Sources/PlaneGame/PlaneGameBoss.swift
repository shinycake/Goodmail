public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A boss: it slides in under the ceiling, moves and attacks until its hits run out, then comes apart. Its status
/// moves on only through `strike(_:)` and `advance(by:towardX:on:scroll:attacking:)`.
///
/// Its status is its only state. Everything a kind does is worked out from its kind, number, age, hits left and
/// status, with the plane's x, the field and the scroll; `position` and `copies` are where `place(on:)` put it.
public struct PlaneGameBoss: Equatable, Sendable {
    /// The roster, in the order the bosses come. After the last, it comes round again a tier angrier.
    public enum Kind: Equatable, Sendable, CaseIterable {
        /// Junk Mail, the spam envelope in a crown, which drops spam.
        case junk
        /// The Phisher, the at sign with a line and hook, which casts lures.
        case phisher
        /// The Reply-All Storm, which dashes from post to post firing replies at the plane.
        case storm
        /// Out of Office, which sends shots back while its sign is up and sends its colleagues.
        case outOfOffice
        /// The Mailing List, which clones itself as it loses hits.
        case mailingList
        /// Inbox Overload, which sends walls of spam and every other boss's attack in turn.
        case overload
    }

    public enum Status: Equatable, Sendable {
        /// Sliding in from above the top edge. Nothing hits it.
        case arriving(elapsed: TimeInterval)
        /// Moving and attacking. `sinceAttack` counts up to the next attack; it has made `attacks` so far.
        case fighting(sinceAttack: TimeInterval, attacks: Int)
        /// Beaten and coming apart.
        case falling(elapsed: TimeInterval)
    }

    public let kind: Kind
    /// 1 for the first boss of a game.
    public let number: Int
    public var position: CGPoint
    /// The other bodies of a Mailing List that has cloned itself, empty for every other boss. Like `position`, the
    /// game moves them only through `place(on:)`.
    public var copies: [CGPoint] = []
    public let hits: Int
    public var hitsLeft: Int
    public var status: Status
    /// Seconds since it started to slide in, which glides are timed from.
    public internal(set) var age: TimeInterval = 0

    /// Boss `number` of a game, above the top edge of `field` and about to slide in. They come in roster order, and
    /// each takes more hits than the last, by less each time.
    public init(number: Int, on field: PlaneGameField) {
        kind = Kind.allCases[(max(number, 1) - 1) % Kind.allCases.count]
        self.number = number
        let later = max(number, 1) - 1
        let ease = PlaneGameRules.bossHitsEase
        hits =
            PlaneGameRules.bossFirstHits + (PlaneGameRules.bossHitsGrowth * later + (later + ease) / 2) / (later + ease)
        hitsLeft = hits
        status = .arriving(elapsed: 0)
        position = .zero
        place(on: field)
    }

    /// Points for beating it.
    public var points: Int {
        PlaneGameRules.bossPoints * number
    }

    /// How close a shot has to come to strike it, or one of its bodies.
    public var radius: CGFloat {
        switch kind {
        case .junk: 44
        case .phisher: 40
        case .storm, .outOfOffice: 42
        case .mailingList: 34
        case .overload: 52
        }
    }

    /// How far above its middle it is drawn, marks of an angrier tier included. It hovers this far under the ceiling,
    /// so none of it ever covers the score.
    public var headroom: CGFloat {
        switch kind {
        case .junk: 64
        case .phisher: 60
        case .storm: 62
        case .outOfOffice: 63
        case .mailingList: 52
        case .overload: 88
        }
    }

    /// Where its bodies are: just the one, but for a Mailing List that has cloned itself.
    public var bodies: [CGPoint] {
        [position] + copies
    }

    /// Past its first phase, when it attacks harder.
    public var isAngry: Bool {
        stage > 0
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

    /// Whether a circle of `radius` at `point` overlaps any of its bodies.
    func touches(_ point: CGPoint, within radius: CGFloat) -> Bool {
        let reach = self.radius + radius
        return bodies.contains { body in
            let dx = body.x - point.x
            let dy = body.y - point.y
            return dx * dx + dy * dy <= reach * reach
        }
    }
}
