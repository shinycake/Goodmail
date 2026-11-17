import MailCore
import MailUI
import UIKit
import UserNotifications

/// Settings over the mail screens. While it's up the screens under it stay as they are, so nothing under the sheet
/// can take it down or move the reader; closing it rebuilds them once, where the reader was, if anything they show
/// changed.
extension SceneCoordinator {
    /// Accounts and preferences, open at `page`, over the mail screens with nothing else over them. Asking again while
    /// it's up does nothing.
    func showSettings(at page: SettingsPage) {
        // A presenter off screen would drop the sheet and leave the cover saying Settings is up.
        guard case .mailbox(let split, let accounts, .none) = screen, let presenter = topViewController(),
            presenter.viewIfLoaded?.window != nil
        else { return }
        let model = model
        let before = Appearance(model)
        let viewModel = SettingsViewModel(
            accounts: { model.accounts },
            signIn: { [weak self] in try await self?.signIn(to: $0) ?? false },
            remove: {
                try await model.removeAccount($0, $1)
                // An account removed from this device alone joins the other devices' accounts it could add.
                try await model.followSharedAccounts()
            },
            update: { try await model.update($0) },
            reorder: { try await model.reorderAccounts($0) },
            signatures: Signatures(
                read: { try await model.signature(for: $0) }, store: { try await model.setSignature($0, for: $1) }),
            closed: { [weak self] in self?.settingsClosed(changed: Appearance(model) != before) })
        viewModel.rules = model.rulesService()
        viewModel.autoReply = { model.autoReplyService(for: $0) }
        viewModel.serverSettings = { model.serverSettingsService(for: $0) }
        viewModel.sharing = model.sharingChoices()
        viewModel.transfer = transferActions
        if model.pushRegistrar != nil {
            viewModel.notifications = NotificationChoices(
                read: { await model.notificationLevels() },
                store: { await model.setNotificationLevel($0, for: $1) },
                turnedOff: {
                    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
                })
        }
        viewModel.badges = model.badgeChoices()
        enter(.mailbox(split, accounts: accounts, cover: .settings(page)))
        presenter.present(SettingsScreen.make(model: viewModel, at: page), animated: true)
    }

    /// Settings is gone. The mail screens are rebuilt where the reader was when what they show changed meanwhile,
    /// in Settings or by another device, and the offer that waited for Settings comes up.
    private func settingsClosed(changed: Bool) {
        guard case .mailbox(let split, let accounts, .settings) = screen else { return }
        enter(.mailbox(split, accounts: accounts, cover: .none))
        model.shareSettingsNow()
        if model.accounts.isEmpty {
            showWelcome()
        } else if changed || accounts != model.accounts.map(\.id) {
            showMailboxKeepingPlace()
        }
        offerSharedAccounts()
    }
}

/// What the mail screens are built from that Settings can change.
private struct Appearance: Equatable {
    let accounts: [Account]
    let unsortedInboxAccounts: Set<AccountID>
    let rowDisplay: RowDisplay
    let theme: CombinedTheme

    init(_ model: AppModel) {
        accounts = model.accounts
        unsortedInboxAccounts = Preferences.unsortedInboxAccounts
        rowDisplay = Preferences.rowDisplay
        theme = Preferences.combinedTheme
    }
}
