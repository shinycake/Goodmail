import UIKit

/// Mail screens the minimized messages sit over: they say where their bottom toolbar's buttons are, and hear what
/// the messages take of it.
protocol DraftDockSite: UIViewController {
    /// Told the bottom line, in the screens' view's coordinates, each time it changes.
    var onBottomLineChange: ((BottomLine) -> Void)? { get set }
    /// The bottom line as it stands.
    var bottomLine: BottomLine { get }
    /// What the minimized messages take of the screens' bottom.
    var draftDock: DraftDock { get set }
}
