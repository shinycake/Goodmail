public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A short effect where something happened; it plays out over `PlaneGameBurst.lifetime`.
public struct PlaneGameBurst: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// A bad guy came apart: shot down for `points`, or 0 when it flew into the plane.
        case pop(points: Int)
        /// A shot stopped on something it didn't destroy.
        case tick
        /// The plane caught a pickup.
        case caught
    }

    public static let lifetime: TimeInterval = 0.5

    public let id: Int
    public let kind: Kind
    public let position: CGPoint
    public var age: TimeInterval
}
