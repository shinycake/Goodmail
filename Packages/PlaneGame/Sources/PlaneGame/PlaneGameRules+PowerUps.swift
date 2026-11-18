public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The numbers the power-ups play by.
extension PlaneGameRules {
    /// Power-ups arrive from this many seconds played, never sooner than `powerUpGap` after the last one arrived.
    public static let powerUpsFrom: TimeInterval = 15
    public static let powerUpGap: TimeInterval = 12
    /// How often a power-up arrives, against the other arrivals open at the time.
    public static let powerUpWeight = 1.5
    /// How long Reply All and Express last.
    public static let weaponTime: TimeInterval = 8
    /// How often Express fires.
    public static let rapidFireEvery: TimeInterval = 0.11
    /// How far Reply All's side shots lean from straight up, in degrees.
    public static let spreadAngle = 12.0
    /// How many hits Unsubscribe takes off a boss.
    public static let sweepBossHits = 5
}
