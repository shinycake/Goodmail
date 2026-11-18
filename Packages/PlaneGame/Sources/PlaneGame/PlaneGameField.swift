public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The space the game plays in, in the window's coordinates: origin top left, x to the right, y down.
public struct PlaneGameField: Equatable, Sendable {
    public var size: CGSize
    /// The x range the plane and everything that arrives keep between: the width, clear of the side safe areas.
    public var lanes: ClosedRange<CGFloat>
    /// The height just under the HUD.
    public var ceiling: CGFloat
    /// The height the plane flies at.
    public var row: CGFloat

    public init(size: CGSize, lanes: ClosedRange<CGFloat>, ceiling: CGFloat, row: CGFloat) {
        self.size = size
        self.lanes = lanes
        self.ceiling = ceiling
        self.row = row
    }

    /// The field of a window `size` across with the given safe areas: the lanes keep 12 points inside the sides, the
    /// ceiling sits under the HUD, and the plane flies high enough above the bottom to leave room for a thumb.
    public init(size: CGSize, safeTop: CGFloat, safeLeft: CGFloat, safeBottom: CGFloat, safeRight: CGFloat) {
        let left = safeLeft + 12
        let ceiling = safeTop + 64
        let gap = min(max(size.height * 0.14, 64), 120)
        self.init(
            size: size, lanes: left...max(size.width - safeRight - 12, left), ceiling: ceiling,
            row: max(size.height - safeBottom - gap, ceiling))
    }

    /// How fast the world comes down here against a phone held upright: the travel from ceiling to row over 640
    /// points, kept between 0.35 and 1.3. The scroll and every thing's own extra speed are multiplied by it, so
    /// something takes about as long to come down in any window, a phone turned on its side included.
    public var pace: CGFloat {
        min(max((row - ceiling) / 640, 0.35), 1.3)
    }

    /// Where the plane's launch ends: the middle of the lanes, on the row.
    public var startingPlace: CGPoint {
        CGPoint(x: (lanes.lowerBound + lanes.upperBound) / 2, y: row)
    }

    /// The x range something keeps to when it has to stay `inset` inside the lanes, or the middle of the lanes when
    /// they are narrower than that.
    func lanes(inset: CGFloat) -> ClosedRange<CGFloat> {
        let low = lanes.lowerBound + inset
        let high = lanes.upperBound - inset
        guard low <= high else {
            let middle = (lanes.lowerBound + lanes.upperBound) / 2
            return middle...middle
        }
        return low...high
    }
}
