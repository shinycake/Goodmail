public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What the reader's finger did since the last step.
public struct PlaneGameInput: Equatable, Sendable {
    /// How far the finger moved sideways since the last step, in points.
    public var slide: CGFloat
    /// A finger is down.
    public var isFiring: Bool

    public init(slide: CGFloat = 0, isFiring: Bool = false) {
        self.slide = slide
        self.isFiring = isFiring
    }
}

/// Something a step did that the screen answers with a haptic or a change of phase.
public enum PlaneGameEvent: Equatable, Sendable {
    case shotDown(points: Int)
    /// The plane caught a star or a heart.
    case caught(PlaneGameThing.Kind)
    /// The plane caught a power-up.
    case powered(PlaneGameThing.Kind)
    case hit(livesLeft: Int)
    /// The plane is out of lives and starts to fall.
    case fell
    /// A boss ran out of hits, for `points`.
    case bossDown(points: Int)
}
