public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The numbers rounds play by. A round is the stretch of play that ends with a boss, and each one plays harder than
/// the last.
extension PlaneGameRules {
    /// How fast the heat rises: it is halfway to its most this many rounds after the first.
    public static let heatHalfway = 6.0
    /// At full heat the scroll is this share faster, arrivals come this share more often and bad guys' own speeds are
    /// this share faster. Heat never quite gets there.
    public static let heatScroll = 0.4
    public static let heatArrivals = 0.6
    public static let heatHurry = 0.8

    /// Each boss after the second comes this much sooner than the one before, but never after less ordinary play
    /// than `shortestWaves`.
    public static let bossSooner: TimeInterval = 5
    public static let shortestWaves: TimeInterval = 30

    /// How long ordinary play lasts before boss `number` comes on: 40 s, then 50, 45, 40, 35 and 30 from then on.
    public static func wavesBefore(boss number: Int) -> TimeInterval {
        guard number > 1 else { return firstBossAfter }
        return max(nextBossAfter - bossSooner * Double(number - 2), shortestWaves)
    }

    /// The most things the field holds. Arrivals and what bosses send stop at it; a beaten boss's drops don't.
    public static let fieldHolds = 50

    /// The round each formation starts to arrive in, and how often it comes against the other arrivals.
    public static let veesFromRound = 2
    public static let gatesFromRound = 3
    public static let phishPairsFromRound = 4
    public static let bulkFromRound = 5
    public static let veeWeight = 1.0
    public static let gateWeight = 0.8
    public static let phishPairWeight = 1.0
    public static let bulkWeight = 1.0
    /// The gap between neighbors in a vee of five spam, across and up, its point leading.
    public static let veeSpacing = CGSize(width: 44, height: 34)
    /// Where the four stamps of a gate sit, from its middle, leaving room to fly through.
    public static let gateOffsets: [CGFloat] = [-114, -70, 70, 114]
    /// How far apart a pair of phish arrives.
    public static let pairSpacing: CGFloat = 140
}
