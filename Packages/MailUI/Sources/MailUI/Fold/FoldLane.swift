import UIKit

/// Where a lone floating element, such as the undo toast, the box threads are put away into, or the bar of
/// minimized messages, sits across the screen.
///
/// iPhone Duo held partly folded like a book has a fold down the middle of its inner display. Text there is hard to
/// read and a button there is hard to tap, so Apple's guidance moves elements off it, the way the system moves its
/// alerts and sheets. A fold running top to bottom splits the area in two, and the element takes the wider region.
/// When the two are even, it takes the right one, where the element stays as the device closes toward its outer
/// display. Right means the physical right, as with the bar of controls on the device's side, so Hebrew keeps it
/// too. A fold running side to side, as when the device stands like a laptop, leaves the full width: the toast and
/// the bar already sit low, in the lower region meant for touch.
nonisolated enum FoldLane {
    /// The part of `area` to the side of the first fold in `folds` that runs top to bottom through it, or all of
    /// `area` when none does. Frames are in one coordinate space.
    static func lane(in area: CGRect, folds: [CGRect]) -> CGRect {
        guard
            let fold = folds.first(where: { fold in
                fold.height > fold.width && fold.minX > area.minX && fold.maxX < area.maxX
            })
        else { return area }
        let left = CGRect(x: area.minX, y: area.minY, width: fold.minX - area.minX, height: area.height)
        let right = CGRect(x: fold.maxX, y: area.minY, width: area.maxX - fold.maxX, height: area.height)
        return left.width > right.width ? left : right
    }
}

extension UIView {
    /// The lane across this view, inside its safe area side to side, that a floating element keeps to: off the bar
    /// of controls on the side of iPhone Duo, and off its fold while it's partly folded (`FoldLane`). In this view's
    /// coordinates, from its top to its bottom.
    var foldLane: CGRect {
        let area = bounds.inset(
            by: UIEdgeInsets(top: 0, left: safeAreaInsets.left, bottom: 0, right: safeAreaInsets.right))
        let folds = reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        return FoldLane.lane(in: area, folds: folds)
    }
}
