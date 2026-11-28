import FieldDiagnostics
import MailCore
import MailUI
import UserNotifications

extension AppModel {
    /// What Settings shows and changes, for the sheet over a mail window or for the Settings window. Sign-ins show
    /// over the window `signIn` names; `closed` runs once Settings is gone and its changes are stored.
    func settingsViewModel(
        signIn: AccountSignIn, transfer: TransferActions?, closed: @escaping () -> Void
    ) -> SettingsViewModel {
        // The model lasts as long as the app.
        let model = self
        let viewModel = SettingsViewModel(
            accounts: { model.accounts },
            signIn: { try await signIn.signIn(to: $0) },
            remove: {
                try await model.removeAccount($0, $1)
                // An account removed from this device alone joins the other devices' accounts it could add.
                try await model.followSharedAccounts()
            },
            update: { try await model.update($0) },
            reorder: { try await model.reorderAccounts($0) },
            signatures: Signatures(
                read: { try await model.signature(for: $0) }, store: { try await model.setSignature($0, for: $1) }),
            closed: closed)
        viewModel.rules = model.rulesService
        viewModel.storage = model.storageSettings()
        viewModel.diagnostics = DiagnosticsModel(archive: .app)
        viewModel.autoReply = { model.autoReplyService(for: $0) }
        viewModel.serverSettings = { model.serverSettingsService(for: $0) }
        viewModel.sharing = model.sharingChoices()
        viewModel.transfer = transfer
        if model.pushRegistrar != nil {
            viewModel.notifications = NotificationChoices(
                read: { await model.notificationLevels() },
                store: { await model.setNotificationLevel($0, for: $1) },
                turnedOff: {
                    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
                })
        }
        viewModel.badges = model.badgeChoices()
        viewModel.watch = model.watchChoices
        return viewModel
    }
}
