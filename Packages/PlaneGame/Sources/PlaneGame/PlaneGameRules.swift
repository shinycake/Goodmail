public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Every number the game plays by, in points and seconds, in one place to tune.
public enum PlaneGameRules {
    // The plane.

    public static let lives = 3
    public static let planeRadius: CGFloat = 11
    /// How far below the bottom edge a plane that comes up from there starts.
    public static let belowField: CGFloat = 60
    /// How long a hit plane blinks and can't be hit again.
    public static let shakenFor: TimeInterval = 1.5
    /// How long the plane takes to tumble off the bottom once it is out of lives.
    public static let fallTime: TimeInterval = 1.0
    /// Radians of bank for each point a second the plane slides sideways, and the most it banks either way.
    public static let bankPerSpeed = 0.0016
    public static let maxBank = 0.5
    /// How quickly the bank catches up with the plane's slide, a share of the gap a second.
    public static let bankEasing = 10.0
    /// How fast the plane turns over while it falls, in radians a second.
    public static let tumbleSpeed = 7.0

    /// The dots behind the plane: one every `trailEvery` seconds, `trailLength` of them in steady flight.
    public static let trailEvery: TimeInterval = 0.03
    public static let trailLength = 14
    /// The longest the trail gets, measured along it, so a fast drag or the fall can't draw a long straight line.
    public static let trailReach: CGFloat = 90

    // Shooting.

    public static let fireEvery: TimeInterval = 0.22
    public static let shotSpeed: CGFloat = 560
    public static let shotRadius: CGFloat = 3

    // The world.

    /// Scroll speed at the start and after `hardeningTime`, rising evenly between, on a field whose pace is 1.
    public static let cruisingSpeed: CGFloat = 150
    public static let topSpeed: CGFloat = 270
    /// How long the game takes to reach its hardest, its fastest scroll and its quickest arrivals.
    public static let hardeningTime: TimeInterval = 120
    /// How long the scroll takes to ease up to speed once the plane sets off.
    public static let rampTime: TimeInterval = 1.2

    /// The longest step the world takes at once. Longer ones are split, so a shot can't pass through a bad guy.
    public static let longestStep: TimeInterval = 1.0 / 60
    /// The most one call to `advance` moves the world on. The screen caps its frames well below this; a longer gap is
    /// a pause, which shouldn't play out all at once.
    public static let longestAdvance: TimeInterval = 1

    // Arrivals.

    public static let firstArrival: TimeInterval = 2.0
    /// Time between arrivals at the start and after `hardeningTime`, shrinking evenly between.
    public static let firstInterval: TimeInterval = 1.4
    public static let lastInterval: TimeInterval = 0.55
    /// When stamps, postmarks, rows of three spam and phish start to arrive, in seconds played. Until stamps come, the
    /// game brings only single spam and stars.
    public static let stampsFrom: TimeInterval = 8
    public static let postmarksFrom: TimeInterval = 14
    public static let spamRowsFrom: TimeInterval = 20
    public static let phishFrom: TimeInterval = 30
    /// Things arrive this far above the top edge and are removed this far past the bottom edge.
    public static let arriveBeyond: CGFloat = 40
    public static let leaveBeyond: CGFloat = 60
    /// How often each kind of arrival comes, against the others open at the time.
    public static let spamWeight = 4.0
    public static let spamRowWeight = 1.5
    public static let stampWeight = 2.0
    public static let postmarkWeight = 1.5
    public static let phishWeight = 1.5
    public static let starWeight = 1.0
    public static let heartWeight = 0.8
    /// The gap between the spam in a row of three, across and down, on a slant.
    public static let rowSpacing = CGSize(width: 52, height: 30)

    // How things move. Extra speeds are on a field whose pace is 1.

    /// Spam falls this much faster than the world and weaves side to side.
    public static let spamExtraSpeed: CGFloat = 70
    public static let spamWeave: CGFloat = 22
    public static let spamWeavePeriod: TimeInterval = 1.3
    /// Phish falls a little faster than the world and drifts toward the plane's x.
    public static let phishExtraSpeed: CGFloat = 20
    public static let phishDrift: CGFloat = 45
    /// Postmarks sway this far, side to side, once a period.
    public static let postmarkSway: CGFloat = 50
    public static let postmarkSwayPeriod: TimeInterval = 2.4
    /// How fast stamps and stars turn, in degrees a second.
    public static let stampSpin = 25.0
    public static let starSpin = 90.0

    // Scoring.

    public static let starPoints = 50
}
