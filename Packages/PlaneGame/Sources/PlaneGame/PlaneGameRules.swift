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
    /// How far toward the trailing edge the plane may go, as a share of the width.
    public static let planeReach = 0.62
    /// Where the plane's launch loop ends, as a share of the field's width and height.
    public static let startAt = CGPoint(x: 0.22, y: 0.45)
    /// How long a hit plane blinks and can't be hit again.
    public static let shakenFor: TimeInterval = 1.5
    /// How long the plane takes to tumble off the bottom once it is out of lives.
    public static let fallTime: TimeInterval = 1.0
    /// Radians of tilt for each point a second the plane climbs or dives, and the most it tilts.
    public static let tiltPerSpeed = 0.0016
    public static let maxTilt = 0.7
    /// How quickly the tilt catches up with the plane's climb, a share of the gap a second.
    public static let tiltEasing = 10.0
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

    /// Scroll speed at the start and after `hardeningTime`, rising evenly between.
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
    /// Things arrive this far beyond the trailing edge and are removed this far past the leading edge.
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
    /// The gap between the spam in a row of three, along and across.
    public static let rowSpacing = CGSize(width: 52, height: 30)

    // How things move.

    /// Spam comes this much faster than the world and weaves up and down.
    public static let spamExtraSpeed: CGFloat = 70
    public static let spamWeave: CGFloat = 22
    public static let spamWeavePeriod: TimeInterval = 1.3
    /// Phish comes a little faster than the world and drifts toward the plane's height.
    public static let phishExtraSpeed: CGFloat = 20
    public static let phishDrift: CGFloat = 45
    /// Postmarks bob this far, top to bottom, once a period.
    public static let postmarkBob: CGFloat = 50
    public static let postmarkBobPeriod: TimeInterval = 2.4
    /// How fast stamps and stars turn, in degrees a second.
    public static let stampSpin = 25.0
    public static let starSpin = 90.0

    // Scoring.

    public static let starPoints = 50
}
