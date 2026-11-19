import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Junk Mail glides across the lanes and back, dropping spam: one at a time, then one more side by side each level.
extension PlaneGameBoss {
    func junkGlide(on field: PlaneGameField) -> CGFloat {
        let glide = sin(2 * .pi * fightTime * tempo / PlaneGameRules.junkGlidePeriod)
        return sway(glide, reach: PlaneGameRules.junkGlideReach, on: field)
    }

    var junkWait: TimeInterval {
        guard level > 0 else { return PlaneGameRules.junkDropEvery }
        return max(
            PlaneGameRules.junkAngryDropEvery - PlaneGameRules.junkDropQuicker * Double(level - 1),
            PlaneGameRules.junkQuickestDrop)
    }

    func junkDrop(on field: PlaneGameField) -> [Sent] {
        row(of: .spam, count: 1 + level, spacing: PlaneGameRules.junkPairSpacing, on: field)
    }
}
