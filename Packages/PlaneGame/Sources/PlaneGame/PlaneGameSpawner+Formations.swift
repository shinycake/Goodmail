import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The formations later rounds bring: a vee of spam, a gate of stamps, a pair of phish. Each arrives around a random
/// lane with room for its width, and every one of its things is then kept inside the lanes, so a formation in lanes
/// too narrow for it still arrives inside them.
extension PlaneGameSpawner {
    /// Five spam in a vee, its point leading.
    static func spamVee(in field: PlaneGameField, using generator: inout SeededGenerator) -> [Arrival] {
        let spacing = PlaneGameRules.veeSpacing
        let lane = randomLane(for: .spam, extra: 2 * spacing.width, in: field, using: &generator)
        return (-2...2).map { step in
            arrival(
                .spam, x: lane + CGFloat(step) * spacing.width,
                y: -PlaneGameRules.arriveBeyond - CGFloat(abs(step)) * spacing.height, in: field)
        }
    }

    /// Four stamps in a row with a gap in the middle to fly through.
    static func stampGate(in field: PlaneGameField, using generator: inout SeededGenerator) -> [Arrival] {
        let offsets = PlaneGameRules.gateOffsets
        let lane = randomLane(for: .stamp, extra: offsets.map(abs).max() ?? 0, in: field, using: &generator)
        return offsets.map { arrival(.stamp, x: lane + $0, y: -PlaneGameRules.arriveBeyond, in: field) }
    }

    /// Two phish side by side, closing on the plane from either side.
    static func phishPair(in field: PlaneGameField, using generator: inout SeededGenerator) -> [Arrival] {
        let half = PlaneGameRules.pairSpacing / 2
        let lane = randomLane(for: .phish, extra: half, in: field, using: &generator)
        return [-half, half].map { arrival(.phish, x: lane + $0, y: -PlaneGameRules.arriveBeyond, in: field) }
    }

    private static func arrival(_ kind: PlaneGameThing.Kind, x: CGFloat, y: CGFloat, in field: PlaneGameField)
        -> Arrival
    {
        Arrival(kind: kind, position: CGPoint(x: field.lanes(inset: kind.radius + kind.swing).clamping(x), y: y))
    }
}
