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

    /// Hits for the first boss, and how many more each one after it takes, up to `bossMostHits`.
    public static let bossFirstHits = 20
    public static let bossMoreHits = 8
    public static let bossMostHits = 44
    /// Points for a boss, times its number.
    public static let bossPoints = 250
    /// How far apart the two pickups a beaten boss leaves are.
    public static let bossDropSpacing: CGFloat = 48

    /// Junk Mail glides across the lanes and back once a period, never farther than `junkGlideReach` from the
    /// middle, so it is no faster in a wide window. It drops spam: one at a time, then two side by
    /// side, this far apart, once it is down to half its hits.
    public static let junkGlidePeriod: TimeInterval = 5
    public static let junkGlideReach: CGFloat = 200
    public static let junkDropEvery: TimeInterval = 1.1
    public static let junkAngryDropEvery: TimeInterval = 0.8
    public static let junkPairSpacing: CGFloat = 52

    /// The Phisher creeps toward the plane's x and casts a fan of lures: three, then five once it is down to half
    /// its hits.
    public static let phisherCreep: CGFloat = 70
    public static let phisherCastEvery: TimeInterval = 1.5
    public static let phisherAngryCastEvery: TimeInterval = 1.3
    public static let phisherLures = 3
    public static let phisherAngryLures = 5
    /// Lures fall this much faster than the world, the outermost spreading sideways this fast.
    public static let lureExtraSpeed: CGFloat = 150
    public static let lureSpread: CGFloat = 60
}
