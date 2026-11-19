public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The numbers the bosses after the first two play by. Speeds are on a field whose pace is 1; times are at the first
/// tier's tempo. "Quicker" is how much shorter a wait gets each level, down to the "quickest".
extension PlaneGameRules {
    /// Replies fall this much faster than the world. Shots pass through them.
    public static let replyExtraSpeed: CGFloat = 170

    /// The Reply-All Storm's posts are a walk this share of its reach apart, wrapping round, never farther than
    /// `stormReach` from the middle. It dashes between them this fast.
    public static let stormWalk = 0.618034
    public static let stormReach: CGFloat = 200
    public static let stormDash: CGFloat = 420
    /// The wait before each burst of replies, and before each echo within one.
    public static let stormReplyEvery: TimeInterval = 2.0
    public static let stormQuicker: TimeInterval = 0.25
    public static let stormQuickestReply: TimeInterval = 1.25
    public static let stormEchoGap: TimeInterval = 0.35
    /// Replies in a fan slide this much faster than their neighbors. The middle one is aimed at the plane, sliding at
    /// most `stormMostAim`, and taking at least `stormShortestFlight` to reach the plane's row.
    public static let stormFan: CGFloat = 55
    public static let stormMostAim: CGFloat = 260
    public static let stormShortestFlight: TimeInterval = 0.4

    /// Out of Office's sign is up this long after the fight starts and after each attack. It creeps over the plane
    /// this fast while it is up, and sends its colleagues, phish, this far apart.
    public static let oooSignUpFor: TimeInterval = 2.4
    public static let oooCreep: CGFloat = 70
    public static let oooEvery: TimeInterval = 5.2
    public static let oooQuicker: TimeInterval = 0.6
    public static let oooQuickest: TimeInterval = 3.6
    public static let oooSpacing: CGFloat = 64

    /// The Mailing List's bodies weave once a period, never farther than `listReach` from the middle, and there are
    /// never more than `listMostBodies`.
    public static let listMostBodies = 4
    public static let listPeriod: TimeInterval = 4.2
    public static let listReach: CGFloat = 170
    public static let listEvery: TimeInterval = 1.5
    public static let listQuicker: TimeInterval = 0.2
    public static let listQuickest: TimeInterval = 0.9

    /// Inbox Overload patrols across its reach and back once a period, and its walls' spam are this far apart.
    public static let overloadPeriod: TimeInterval = 7
    public static let overloadReach: CGFloat = 200
    public static let overloadEvery: TimeInterval = 1.6
    public static let overloadQuicker: TimeInterval = 0.25
    public static let overloadQuickest: TimeInterval = 0.85
    public static let overloadSpacing: CGFloat = 56
}
