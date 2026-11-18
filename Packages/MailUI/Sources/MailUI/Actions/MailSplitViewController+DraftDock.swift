import UIKit

extension MailSplitViewController: DraftDockSite {
    /// The line the undo toast sits on: the same lane, end buttons and toolbar.
    var bottomLine: BottomLine {
        BottomLine(lane: toastLane, ends: toolbarEnds(), bottom: view.bounds.maxY, barsInset: aboveToolbars())
    }
}
