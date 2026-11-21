import MailCore
import MailUI

extension SceneCoordinator {
    /// Shows what another device handed off, in this window, laid out as this window is: a viewer stays a viewer, and
    /// a message window reads the handed-off conversation alone, or becomes a viewer when nothing is read. Its list
    /// may not be synced here yet (`WindowState.ListCheck.handedOff`).
    func showHandedOff(_ state: WindowState) {
        guard !model.accounts.isEmpty else { return }
        let kept = state.keeping(model.accounts.map(\.id))
        let laidOut =
            switch shown.layout {
            case .viewer: kept.asViewer
            case .message: kept.asMessage ?? kept.asViewer
            }
        showMailbox(laidOut)
        followOwnLists(.handedOff)
    }
}
