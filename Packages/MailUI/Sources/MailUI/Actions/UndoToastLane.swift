import UIKit

/// A screen whose bottom toolbar can carry the undo toast in its middle, on one line with the buttons at its ends,
/// as the mailbox list's does between Search and Compose.
protocol UndoToastLane: UIViewController {
    /// The toolbar's buttons that flank an empty middle, or none while something fills it.
    var toolbarEnds: [UIBarButtonItem] { get }
}

extension UndoToastLane {
    /// Tells the split view to place the toast again, after the toolbar's middle opened or filled.
    func toolbarEndsChanged() {
        splitViewController?.view.setNeedsLayout()
    }
}

/// Where the undo toast sits over the shown screen.
nonisolated enum UndoToastPlacement: Equatable {
    /// Above the bottom toolbar, or above the home indicator when there is none, `inset` from the bottom.
    case above(inset: CGFloat)
    /// In the middle of the bottom toolbar, centered on the line its end buttons sit on.
    case inToolbar(centerY: CGFloat)

    /// The least room the toast leaves between itself and a toolbar button.
    static let buttonGap: CGFloat = 12

    /// On the line of `ends`, the frames of the toolbar's end buttons, when a toast of `toastSize` centered on
    /// `midX` stays clear of them; else above the toolbar, `aboveInset` from the bottom.
    static func choose(ends: [CGRect], midX: CGFloat, toastSize: CGSize, aboveInset: CGFloat) -> UndoToastPlacement {
        // How far the toast may reach either way from the middle before it comes too near a button.
        let room = ends.map { $0.midX < midX ? midX - $0.maxX : $0.minX - midX }.min()
        guard let first = ends.first, let room, toastSize.width / 2 <= room - buttonGap else {
            return .above(inset: aboveInset)
        }
        return .inToolbar(centerY: first.midY)
    }

    /// The constant for the toast's bottom constraint against the bottom of `bounds`.
    func bottomConstant(in bounds: CGRect, toastHeight: CGFloat) -> CGFloat {
        switch self {
        case .above(let inset): -inset
        case .inToolbar(let centerY): centerY + toastHeight / 2 - bounds.maxY
        }
    }
}
