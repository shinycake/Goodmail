import MailCore
import MailUI

extension SceneCoordinator {
    /// What the sidebar footer's problem does, as the list's toolbar does on touch: the service's sign-in for one it
    /// turned down, a sync now for an account that can't sync, and registering for alerts again when they paused.
    func fix(_ notice: AccountProblemNotice) async {
        switch notice.problem {
        case .signInRejected: handle(.signInAgain(notice.account.id))
        case .cantSync: try? await model.syncAll()
        case .alertsPaused: await model.refreshPush()
        }
    }
}
