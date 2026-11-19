import MailCore
import MailNotifications

/// What the relay's quiet push asks for: mail in an account was read, filed or deleted on another device or in
/// another app, so alerts this iPhone still shows for it should come down (PushWorker/README.md).
extension AppModel {
    /// Syncs the account the push names, leaving the Inbox's seen mark alone since the reader hasn't looked, then
    /// sweeps the alerts its mail no longer needs. The sweep that follows the store's changes runs too, but iOS may
    /// suspend the app before it gets a turn. Returns whether the sync went through.
    func syncHandledElsewhere(_ target: NewMailFetch.Target) async -> Bool {
        guard let account = target.account(among: accounts) else { return false }
        let synced = await syncChanged(account.id, markingInboxSeen: false)
        await HandledAlerts.dismiss(in: database)
        return synced
    }
}
