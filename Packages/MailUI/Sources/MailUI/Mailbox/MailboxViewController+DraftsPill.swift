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

    func draftsPillDidChange() {
        guard viewIfLoaded?.window != nil else { return }
        navigationController?.view.layoutIfNeeded()
        toolbarEndsChanged()
    }
}
