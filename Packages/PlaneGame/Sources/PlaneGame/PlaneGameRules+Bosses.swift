public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The numbers the bosses play by. Speeds are on a field whose pace is 1.
extension PlaneGameRules {
    /// The first boss comes after this much ordinary play, and each one after it this long after the last one fell.
    public static let firstBossAfter: TimeInterval = 40
    public static let nextBossAfter: TimeInterval = 50
    /// The longest the field is given to empty before a boss comes on.
    public static let clearingAtMost: TimeInterval = 4
    /// How long a boss takes to slide in from above the top edge, and to come apart once beaten.
    public static let bossArrival: TimeInterval = 1.4
    public static let bossFall: TimeInterval = 1.2

    /// Hits for the first boss. Each one after takes more, by less each time: `bossHitsGrowth` more at most, half of
    /// that by boss `bossHitsEase + 1`.
    public static let bossFirstHits = 20
    public static let bossHitsGrowth = 88
    public static let bossHitsEase = 10
    /// The most a boss's level reaches, from its tier and phase together.
    public static let bossMostLevel = 3
    /// Each time round the roster bosses move and attack faster, up to `1 + bossTempoGain` times, halfway there after
    /// `bossTempoEase` times round.
    public static let bossTempoGain = 0.5
    public static let bossTempoEase = 2.0
    /// Points for a boss, times its number.
    public static let bossPoints = 250
    /// How far apart the two pickups a beaten boss leaves are.
    public static let bossDropSpacing: CGFloat = 48

    /// Junk Mail glides across the lanes and back once a period, never farther than `junkGlideReach` from the
    /// middle, so it is no faster in a wide window. It drops spam: one at a time, then one more side by side, this far
    /// apart, each level, dropping quicker each level after the first.
    public static let junkGlidePeriod: TimeInterval = 5
    public static let junkGlideReach: CGFloat = 200
    public static let junkDropEvery: TimeInterval = 1.1
    public static let junkAngryDropEvery: TimeInterval = 0.8
    public static let junkPairSpacing: CGFloat = 52
    public static let junkDropQuicker: TimeInterval = 0.15
    public static let junkQuickestDrop: TimeInterval = 0.5

    /// The Phisher creeps to stay `phisherOffset` to one side of the plane, so a plane that waits under it never
    /// gets to shoot it, and casts a fan of lures: three, then two more each level, at least `lureGap` apart. It holds
    /// still for `phisherHold` after each cast, and creeps slowly enough that a shot fired under it still lands after
    /// the 1.2 seconds it takes to climb, so a plane that slides after it hits it.
    public static let phisherCreep: CGFloat = 35
    public static let phisherOffset: CGFloat = 90
    public static let phisherHold: TimeInterval = 0.5
    public static let phisherCastEvery: TimeInterval = 1.5
    public static let phisherAngryCastEvery: TimeInterval = 1.3
    public static let phisherCastQuicker: TimeInterval = 0.15
    public static let phisherQuickestCast: TimeInterval = 1.0
    public static let phisherLures = 3
    public static let lureGap: CGFloat = 30
    /// Lures fall this much faster than the world, the outermost spreading sideways this fast.
    public static let lureExtraSpeed: CGFloat = 150
    public static let lureSpread: CGFloat = 60
}
