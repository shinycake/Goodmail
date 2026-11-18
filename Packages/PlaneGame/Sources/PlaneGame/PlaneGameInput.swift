public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    public import CoreGraphics
#endif

/// What the reader's finger did since the last step.
public struct PlaneGameInput: Equatable, Sendable {
    /// How far the finger moved since the last step, in flight coordinates.
    public var drag: CGSize
    /// A finger is down.
    public var isFiring: Bool

    public init(drag: CGSize = .zero, isFiring: Bool = false) {
        self.drag = drag
        self.isFiring = isFiring
    }
}

/// Something a step did that the screen answers with a haptic or a change of phase.
public enum PlaneGameEvent: Equatable, Sendable {
    case shotDown(points: Int)
    case caught(PlaneGameThing.Kind)
    case hit(livesLeft: Int)
    /// The plane is out of lives and starts to fall.
    case fell
}
