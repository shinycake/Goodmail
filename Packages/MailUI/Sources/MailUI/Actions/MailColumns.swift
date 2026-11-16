import UIKit

/// Which mail screens show side by side in a window wide enough for more than one, such as iPad or iPhone Duo's
/// inner display. The list always stays beside the thread, as Apple's guidance for iPhone Duo describes for Mail;
/// the mailboxes join them as a third column only when the thread keeps a comfortable reading width beside both.
/// Narrower, they're a tap away in the sidebar button.
nonisolated enum MailColumns {
    /// The least width for three columns: the sidebar and list at their usual widths, and the thread at least as
    /// wide as an iPhone's screen.
    static let threeColumnWidth: CGFloat = 1000

    /// The least width the thread takes beside the list: about an iPhone's screen. UIKit's own least width is
    /// wider, and then it lays the list over the thread rather than beside it on narrow regular-width windows,
    /// such as iPad mini in portrait, or iPhone Duo's inner display, where the list (340 points) and the thread fit
    /// side by side only above it.
    static let minimumThreadWidth: CGFloat = 320

    /// How a split view `width` points wide arranges its columns.
    static func displayMode(forWidth width: CGFloat) -> UISplitViewController.DisplayMode {
        width >= threeColumnWidth ? .twoBesideSecondary : .oneBesideSecondary
    }
}
