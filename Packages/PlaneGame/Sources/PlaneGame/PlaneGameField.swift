public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The space the game plays in, in flight coordinates: origin top leading, x toward the trailing edge, y down.
public struct PlaneGameField: Equatable, Sendable {
    public var size: CGSize
    /// The heights the plane and everything that arrives keep between.
    public var band: ClosedRange<CGFloat>
    /// How far from the leading edge the plane keeps, as clear of a camera housing in landscape.
    public var leadingInset: CGFloat

    public init(size: CGSize, band: ClosedRange<CGFloat>, leadingInset: CGFloat = 0) {
        self.size = size
        self.band = band
        self.leadingInset = leadingInset
    }
}
