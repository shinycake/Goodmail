import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// How hard a round plays. Round 1 is the game as it always was; each beaten boss turns it up, by less each time, so
/// it keeps rising and never runs away.
struct PlaneGameHeat: Equatable, Sendable {
    /// 0 in round 1, rising toward 1 and never reaching it.
    let level: Double

    init(round: Int) {
        let later = Double(max(round, 1) - 1)
        level = later / (later + PlaneGameRules.heatHalfway)
    }

    /// The scroll is this many times as fast as in round 1.
    var scroll: CGFloat {
        CGFloat(1 + PlaneGameRules.heatScroll * level)
    }

    /// Arrivals come this many times as often as in round 1.
    var arrivals: Double {
        1 + PlaneGameRules.heatArrivals * level
    }

    /// Bad guys' own speeds are this many times as fast as in round 1.
    var hurry: CGFloat {
        CGFloat(1 + PlaneGameRules.heatHurry * level)
    }
}
