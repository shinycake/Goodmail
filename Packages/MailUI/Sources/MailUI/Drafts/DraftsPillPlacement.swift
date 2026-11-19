import CoreGraphics

/// The geometry of the composer's card around the drafts pill: whether a pill's frame can be aimed at, where a card
/// goes when no pill is on show, and the dot it grows out of or drains into.
nonisolated enum DraftsPillPlacement {
    /// The chip's size by the corner, where there is no pill to measure: about the pill's.
    static let chipSize = CGSize(width: 76, height: 44)
    /// How far the corner chip keeps from the side of its lane, as the toolbar's buttons do.
    static let cornerInset: CGFloat = 16
    /// How far below the screen the corner chip lies, so none of it shows.
    static let cornerDrop: CGFloat = 24
    static let dotSize: CGFloat = 6

    /// Whether `frame`, a pill's in `bounds`, is where the toolbar placed it: not empty and in the lower half. A
    /// pill laid out before its toolbar, or in a bar down the side, fails.
    static func isPlaced(_ frame: CGRect, in bounds: CGRect) -> Bool {
        !frame.isEmpty && frame.midY > bounds.midY
    }

    /// Where a card leaving with no pill on show comes to rest: chip-sized, just below the bottom of `bounds`, at the
    /// leading end of `lane`, the side the pill is on.
    static func corner(lane: CGRect, bounds: CGRect, rightToLeft: Bool) -> CGRect {
        let x = rightToLeft ? lane.maxX - cornerInset - chipSize.width : lane.minX + cornerInset
        return CGRect(origin: CGPoint(x: x, y: bounds.maxY + cornerDrop), size: chipSize)
    }

    /// The dot centred on `point`, the pill's icon, that a card drains into or grows out of.
    static func dot(at point: CGPoint) -> CGRect {
        CGRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2, width: dotSize, height: dotSize)
    }
}
