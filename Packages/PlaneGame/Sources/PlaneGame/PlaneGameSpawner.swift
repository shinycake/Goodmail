import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What arrives when: one thing, or a row of three spam, every so often, the gap shrinking as the game goes on. Each
/// kind waits for its unlock time, hearts come only while a life is missing, and a power-up only while none is in
/// play and the last one arrived long enough ago.
struct PlaneGameSpawner: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// The next arrival is due at `due`, in seconds played.
        case waiting(due: TimeInterval)
        /// The plane is down, so nothing more arrives.
        case closed
    }

    /// One thing to put on the field.
    struct Arrival: Equatable, Sendable {
        let kind: PlaneGameThing.Kind
        let position: CGPoint
    }

    /// What the field holds that decides what may arrive.
    struct Openings: Equatable, Sendable {
        var livesMissing: Bool
        var powerUpInPlay: Bool
    }

    /// The shapes an arrival can take, picked at random by weight from those open at the time.
    enum Pattern: Equatable, CaseIterable {
        case spam, stamp, postmark, phish, star, heart
        /// Three spam on a slant, each one across from and above the one before.
        case spamRow
        /// One of the four power-ups, picked evenly.
        case powerUp

        var weight: Double {
            switch self {
            case .spam: PlaneGameRules.spamWeight
            case .spamRow: PlaneGameRules.spamRowWeight
            case .stamp: PlaneGameRules.stampWeight
            case .postmark: PlaneGameRules.postmarkWeight
            case .phish: PlaneGameRules.phishWeight
            case .star: PlaneGameRules.starWeight
            case .heart: PlaneGameRules.heartWeight
            case .powerUp: PlaneGameRules.powerUpWeight
            }
        }
    }

    private(set) var state = State.waiting(due: PlaneGameRules.firstArrival)
    /// The soonest the next power-up may arrive, in seconds played.
    private(set) var nextPowerUp = PlaneGameRules.powerUpsFrom

    /// The time between arrivals `elapsed` seconds into the game, on a field whose breadth is 1.
    static func interval(at elapsed: TimeInterval) -> TimeInterval {
        let hardening = min(max(elapsed / PlaneGameRules.hardeningTime, 0), 1)
        return PlaneGameRules.firstInterval + (PlaneGameRules.lastInterval - PlaneGameRules.firstInterval) * hardening
    }

    /// Everything due by `elapsed`, placed just above the top edge of `field`.
    mutating func arrivals(
        at elapsed: TimeInterval, in field: PlaneGameField, openings: Openings, using generator: inout SeededGenerator
    ) -> [Arrival] {
        var arrivals: [Arrival] = []
        var openings = openings
        while case .waiting(let due) = state, due <= elapsed {
            let open = Pattern.allCases.filter { isOpen($0, at: due, openings) }
            let pattern = Self.pick(from: open, using: &generator)
            if pattern == .powerUp {
                nextPowerUp = due + PlaneGameRules.powerUpGap
                openings.powerUpInPlay = true
            }
            arrivals += Self.place(pattern, in: field, using: &generator)
            state = .waiting(due: due + Self.interval(at: due) / Double(field.breadth))
        }
        return arrivals
    }

    /// Ordinary play carries on at `elapsed` after a boss: the next arrival is an interval away on `field`.
    mutating func resume(at elapsed: TimeInterval, on field: PlaneGameField) {
        guard case .waiting = state else { return }
        state = .waiting(due: elapsed + Self.interval(at: elapsed) / Double(field.breadth))
    }

    /// Stops arrivals for good.
    mutating func close() {
        state = .closed
    }

    private static func pick(from open: [Pattern], using generator: inout SeededGenerator) -> Pattern {
        var roll = Double.random(in: 0..<open.map(\.weight).reduce(0, +), using: &generator)
        for pattern in open {
            if roll < pattern.weight { return pattern }
            roll -= pattern.weight
        }
        return open[open.count - 1]
    }

    private func isOpen(_ pattern: Pattern, at elapsed: TimeInterval, _ openings: Openings) -> Bool {
        switch pattern {
        case .spam, .star: true
        case .stamp: elapsed >= PlaneGameRules.stampsFrom
        case .postmark: elapsed >= PlaneGameRules.postmarksFrom
        case .spamRow: elapsed >= PlaneGameRules.spamRowsFrom
        case .phish: elapsed >= PlaneGameRules.phishFrom
        case .heart: openings.livesMissing
        case .powerUp: !openings.powerUpInPlay && elapsed >= nextPowerUp
        }
    }

    private static func place(_ pattern: Pattern, in field: PlaneGameField, using generator: inout SeededGenerator)
        -> [Arrival]
    {
        switch pattern {
        case .spam: one(.spam, in: field, using: &generator)
        case .stamp: one(.stamp, in: field, using: &generator)
        case .postmark: one(.postmark, in: field, using: &generator)
        case .phish: one(.phish, in: field, using: &generator)
        case .star: one(.star, in: field, using: &generator)
        case .heart: one(.heart, in: field, using: &generator)
        case .powerUp: one(randomPowerUp(using: &generator), in: field, using: &generator)
        case .spamRow: spamRow(in: field, using: &generator)
        }
    }

    /// One of the four power-ups, each as likely as the others.
    static func randomPowerUp(using generator: inout SeededGenerator) -> PlaneGameThing.Kind {
        let powerUps = PlaneGameThing.Kind.powerUps
        return powerUps[Int.random(in: 0..<powerUps.count, using: &generator)]
    }

    private static func one(
        _ kind: PlaneGameThing.Kind, in field: PlaneGameField, using generator: inout SeededGenerator
    )
        -> [Arrival]
    {
        let lane = randomLane(for: kind, extra: 0, in: field, using: &generator)
        return [Arrival(kind: kind, position: CGPoint(x: lane, y: -PlaneGameRules.arriveBeyond))]
    }

    private static func spamRow(in field: PlaneGameField, using generator: inout SeededGenerator) -> [Arrival] {
        let y = -PlaneGameRules.arriveBeyond
        let spacing = PlaneGameRules.rowSpacing
        let lane = randomLane(for: .spam, extra: spacing.width, in: field, using: &generator)
        return (0..<3).map { index in
            Arrival(
                kind: .spam,
                position: CGPoint(x: lane + CGFloat(index - 1) * spacing.width, y: y - CGFloat(index) * spacing.height))
        }
    }

    /// An x for `kind` to arrive at, far enough inside the lanes that it, its swing and `extra` stay inside.
    private static func randomLane(
        for kind: PlaneGameThing.Kind, extra: CGFloat, in field: PlaneGameField, using generator: inout SeededGenerator
    ) -> CGFloat {
        CGFloat.random(in: field.lanes(inset: kind.radius + kind.swing + extra), using: &generator)
    }
}
