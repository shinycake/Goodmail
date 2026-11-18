public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A shot from the plane, flying toward the trailing edge.
public struct PlaneGameShot: Equatable, Sendable, Identifiable {
    public let id: Int
    public var position: CGPoint
}
