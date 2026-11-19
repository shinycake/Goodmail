import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The Mailing List clones itself: one body, then one more at each phase, more from the start in later tiers. The
/// bodies weave across the lanes spaced evenly around one glide, share one pool of hits, and each forwards a spam
/// at every attack. Angry, the lead sends Bulk Mail every third attack instead.
extension PlaneGameBoss {
    var mailingListBodies: Int {
        min(1 + stage + tier, PlaneGameRules.listMostBodies)
    }

    /// The x of each body, the lead first.
    func mailingListPlaces(on field: PlaneGameField) -> [CGFloat] {
        let count = mailingListBodies
        let turn = fightTime * tempo / PlaneGameRules.listPeriod
        return (0..<count).map { index in
            let glide = sin(2 * .pi * (turn + Double(index) / Double(count)))
            return sway(glide, reach: PlaneGameRules.listReach, on: field)
        }
    }

    var mailingListWait: TimeInterval {
        max(PlaneGameRules.listEvery - PlaneGameRules.listQuicker * Double(level), PlaneGameRules.listQuickest)
    }

    /// One spam from under every body, or Bulk Mail from the lead on every third forward once it is angry. Forwards
    /// are counted whoever sends them, so borrowing doesn't line up with the third.
    func mailingListForwards(on field: PlaneGameField, attack: Int) -> [Sent] {
        let forwards = (0..<attack).count { attacker(at: $0) == .mailingList }
        let bulk = level > 0 && forwards % 3 == 2
        return bodies.enumerated().map { index, body in
            let kind: PlaneGameThing.Kind = bulk && index == 0 ? .bulk : .spam
            let x = field.lanes(inset: kind.radius + kind.swing).clamping(body.x)
            return Sent(kind: kind, position: CGPoint(x: x, y: body.y + radius), drift: 0)
        }
    }
}
