import UIKit

/// A screen with a bar of its own along the bottom, such as the chat's message field, which the undo toast sits above
/// rather than covers. The bar may ride on the keyboard, whose window would hide a toast below it.
protocol UndoToastFloor: UIViewController {
    /// The bar the toast stays above, or `nil` while none shows.
    var toastFloor: UIView? { get }

    /// How much of the screen the toast now covers above the bar, from the bar's top, or zero while none shows, so
    /// the screen can keep its newest content clear of it.
    func toastCovers(_ height: CGFloat)
}

extension UndoToastFloor {
    /// Tells the split view to place the toast again, after the bar moved or came and went.
    func toastFloorChanged() {
        splitViewController?.view.setNeedsLayout()
    }
}
