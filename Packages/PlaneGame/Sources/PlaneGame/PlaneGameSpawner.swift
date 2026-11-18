import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What arrives when: one thing, or a row of three spam, every so often, the gap shrinking as the game goes on. Each
/// kind waits for its unlock time, and hearts come only while a life is missing.
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

    /// The shapes an arrival can take, picked at random by weight from those open at the time.
    enum Pattern: Equatable {
        case one(PlaneGameThing.Kind)
        /// Three spam, staggered one behind and below another.
        case spamRow

        static let all = PlaneGameThing.Kind.allCases.map(Pattern.one) + [.spamRow]

        var weight: Double {
            switch self {
            case .one(.spam): PlaneGameRules.spamWeight
            case .spamRow: PlaneGameRules.spamRowWeight
            case .one(.stamp): PlaneGameRules.stampWeight
            case .one(.postmark): PlaneGameRules.postmarkWeight
            case .one(.phish): PlaneGameRules.phishWeight
            case .one(.star): PlaneGameRules.starWeight
            case .one(.heart): PlaneGameRules.heartWeight
            }
        }

        func isOpen(at elapsed: TimeInterval, livesMissing: Bool) -> Bool {
            switch self {
            case .one(.spam), .one(.stamp), .one(.star): true
            case .one(.postmark): elapsed >= PlaneGameRules.postmarksFrom
            case .spamRow: elapsed >= PlaneGameRules.spamRowsFrom
            case .one(.phish): elapsed >= PlaneGameRules.phishFrom
            case .one(.heart): livesMissing
            }
        }
    }

    private(set) var state = State.waiting(due: PlaneGameRules.firstArrival)

    /// The time between arrivals `elapsed` seconds into the game.
    static func interval(at elapsed: TimeInterval) -> TimeInterval {
        let hardening = min(max(elapsed / PlaneGameRules.hardeningTime, 0), 1)
        return PlaneGameRules.firstInterval + (PlaneGameRules.lastInterval - PlaneGameRules.firstInterval) * hardening
    }

    /// Everything due by `elapsed`, placed just beyond the trailing edge of `field`.
    mutating func arrivals(
        at elapsed: TimeInterval, in field: PlaneGameField, livesMissing: Bool,
        using generator: inout SeededGenerator
    ) -> [Arrival] {
        var arrivals: [Arrival] = []
        while case .waiting(let due) = state, due <= elapsed {
            let open = Pattern.all.filter { $0.isOpen(at: due, livesMissing: livesMissing) }
            arrivals += Self.place(Self.pick(from: open, using: &generator), in: field, using: &generator)
            state = .waiting(due: due + Self.interval(at: due))
        }
        return arrivals
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

    private static func place(_ pattern: Pattern, in field: PlaneGameField, using generator: inout SeededGenerator)
        -> [Arrival]
    {
        let x = field.size.width + PlaneGameRules.arriveBeyond
        switch pattern {
        case .one(let kind):
            let lane = randomLane(for: kind, extra: 0, in: field.band, using: &generator)
            return [Arrival(kind: kind, position: CGPoint(x: x, y: lane))]
        case .spamRow:
            let spacing = PlaneGameRules.rowSpacing
            let lane = randomLane(for: .spam, extra: spacing.height, in: field.band, using: &generator)
            return (0..<3).map { index in
                Arrival(
                    kind: .spam,
                    position: CGPoint(
                        x: x + CGFloat(index) * spacing.width, y: lane + CGFloat(index - 1) * spacing.height))
            }
        }
    }

    /// A height for `kind` to arrive at, far enough inside `band` that it, its swing and `extra` stay inside.
    private static func randomLane(
        for kind: PlaneGameThing.Kind, extra: CGFloat, in band: ClosedRange<CGFloat>,
        using generator: inout SeededGenerator
    ) -> CGFloat {
        let inset = kind.radius + kind.swing + extra
        let low = band.lowerBound + inset
        let high = band.upperBound - inset
        guard low < high else { return (band.lowerBound + band.upperBound) / 2 }
        return CGFloat.random(in: low...high, using: &generator)
    }
}
