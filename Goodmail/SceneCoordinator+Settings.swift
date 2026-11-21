import MailCore
import MailUI
import UIKit

/// Settings over the mail screens. While it's up the screens under it stay as they are, so nothing under the sheet
/// can take it down or move the reader; closing it rebuilds them once, where the reader was, if anything they show
/// changed. Where Settings has a window of its own, the mail windows follow once that window closes
/// (`SettingsWindowCoordinator`).
extension SceneCoordinator {
    /// Accounts and preferences, open at `page`, over the mail screens with nothing else over them. Asking again while
    /// it's up does nothing.
    func showSettings(at page: SettingsPage) {
        guard case .mailbox(let accounts, .none) = screen, let presenter = topViewController() else {
            return
        }
        // A presenter off screen would drop the sheet and leave the cover saying Settings is up; the navigation
        // presents only once the window is on screen, as after a cold launch (D14).
        guard presenter.viewIfLoaded?.window != nil else { return }
        let before = Appearance(model)
        let viewModel = model.settingsViewModel(
            signIn: accountSignIn, transfer: transferActions,
            closed: { [weak self, model] in self?.settingsClosed(changed: Appearance(model) != before) })
        enter(.mailbox(accounts: accounts, cover: .settings(page)))
        presenter.present(SettingsScreen.make(model: viewModel, at: page), animated: true)
    }

    /// Settings is gone. The mail screens are rebuilt where the reader was when what they show changed meanwhile,
    /// in Settings or by another device, and the offer that waited for Settings comes up.
    private func settingsClosed(changed: Bool) {
        guard case .mailbox(let accounts, .settings) = screen else { return }
        enter(.mailbox(accounts: accounts, cover: .none))
        model.shareSettingsNow()
        followSettings(changed: changed, builtFor: accounts)
    }

    /// The Settings window closed: the mail screens follow what changed while it was up, as they do when the sheet
    /// closes. Under the other devices' offer they stay as they are, as they do for a change another device makes.
    func settingsWindowClosed(changed: Bool) {
        guard let accounts = uncoveredMail else { return }
        followSettings(changed: changed, builtFor: accounts)
    }

    private func followSettings(changed: Bool, builtFor accounts: [AccountID]) {
        if model.accounts.isEmpty {
            showWelcome()
        } else if changed || accounts != model.accounts.map(\.id) {
            showMailbox()
        }
        offerSharedAccounts()
    }
}

/// What the mail screens are built from that Settings can change.
struct Appearance: Equatable {
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
