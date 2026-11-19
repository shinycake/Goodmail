import UIKit

extension MailboxViewController: DraftsPillSite {
    /// The list's toolbar is on show and still: in a window, on top of its stack, browsing, not searching, the
    /// toolbar showing, and no push or pop under way.
    var showsDraftsPill: Bool {
        guard let navigationController, viewIfLoaded?.window != nil, !isEditing, search?.isActive != true else {
            return false
        }
        return navigationController.topViewController === self && !navigationController.isToolbarHidden
            && transitionCoordinator == nil
    }

    /// The whole window is laid out, not just this navigation stack: on iPad the split view places the column's
    /// toolbar items, and a pill shown there for the first time has no frame until it does.
    func draftsPillDidChange() {
        guard let window = viewIfLoaded?.window else { return }
        window.layoutIfNeeded()
        toolbarEndsChanged()
    }
}
