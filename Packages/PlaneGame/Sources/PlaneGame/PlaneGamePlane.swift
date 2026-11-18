public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The reader's plane.
public struct PlaneGamePlane: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Flying its loop onto the field. `elapsed` is negative while it waits to set off.
        case launching(LoopPath, elapsed: TimeInterval)
        case flying
        /// Just hit: it can't be hit again for `remaining` seconds.
        case shaken(remaining: TimeInterval)
        /// Out of lives and falling.
        case down(elapsed: TimeInterval)
    }

    public var position: CGPoint
    /// Radians clockwise from pointing at the trailing edge.
    public var heading: Double
    /// Where it has just been, nearest first, at most 14 points, carried back by the scroll.
    public var trail: [CGPoint]
    public var status: Status
}
