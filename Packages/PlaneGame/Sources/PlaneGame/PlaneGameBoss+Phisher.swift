import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The Phisher keeps to one side of the plane and casts fans of lures, two more each level, the fan widening so it
/// can always be threaded.
extension PlaneGameBoss {
    /// Creeps toward its place beside the plane, holding still for `phisherHold` after each attack. Its creep stays
    /// as slow in every tier, so a shot fired under it still lands.
    mutating func phisherCreep(
        by dt: TimeInterval, towardX planeX: CGFloat, on field: PlaneGameField, sinceAttack: TimeInterval
    ) {
        guard sinceAttack >= PlaneGameRules.phisherHold else { return }
        let aim = phisherAim(besideX: planeX, within: field.lanes(inset: radius))
        head(toward: aim, speed: PlaneGameRules.phisherCreep, over: dt)
    }

    var phisherWait: TimeInterval {
        guard level > 0 else { return PlaneGameRules.phisherCastEvery }
        return max(
            PlaneGameRules.phisherAngryCastEvery - PlaneGameRules.phisherCastQuicker * Double(level - 1),
            PlaneGameRules.phisherQuickestCast)
    }

    func phisherCast(on field: PlaneGameField) -> [Sent] {
        let count = PlaneGameRules.phisherLures + 2 * level
        let gap = max(2 * PlaneGameRules.lureSpread / CGFloat(count - 1), PlaneGameRules.lureGap) * field.pace
        return fan(of: .lure, count: count, gap: gap, around: 0)
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
}
