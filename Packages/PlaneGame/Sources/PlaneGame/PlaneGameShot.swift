public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A shot from the plane, flying up.
public struct PlaneGameShot: Equatable, Sendable, Identifiable {
    public let id: Int
    public var position: CGPoint
    /// Its sideways speed, in points a second: 0 straight up, and to each side for Reply All's side shots.
    public let drift: CGFloat
}
