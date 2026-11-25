import MailCore
import MailUI
import UIKit

/// Settings over the mail screens. While it's up the screens under it stay as they are, so nothing under the sheet
/// can take it down or move the reader; closing it rebuilds them once, where the reader was, if anything they show
/// changed. Where Settings has a window of its own, the mail windows beside it follow each change as it is made, and
/// catch up when it closes (`SettingsWindowCoordinator`). Each window compares what it was built from
/// (`Screen.mailbox`).
extension SceneCoordinator {
    /// Accounts and preferences, open at `page`, over the mail screens with nothing else over them. Asking again while
    /// it's up does nothing.
    func showSettings(at page: SettingsPage) {
        guard case .mailbox(let built, .none) = screen, let presenter = topViewController() else {
            return
        }
        // A presenter off screen would drop the sheet and leave the cover saying Settings is up; the navigation
        // presents only once the window is on screen, as after a cold launch (D14).
        guard presenter.viewIfLoaded?.window != nil else { return }
        let viewModel = model.settingsViewModel(
            signIn: accountSignIn, transfer: transferActions, closed: { [weak self] in self?.settingsClosed() })
        enter(.mailbox(built: built, cover: .settings(page)))
        presenter.present(SettingsScreen.make(model: viewModel, at: page), animated: true)
    }

    /// Settings is gone. The mail screens follow what changed meanwhile, in Settings or by another device, and the
    /// offer that waited for Settings comes up.
    private func settingsClosed() {
        guard case .mailbox(let built, .settings) = screen else { return }
        enter(.mailbox(built: built, cover: .none))
        model.shareSettingsNow()
        settingsWindowClosed()
    }

    /// The Settings window closed, or the sheet did: the mail screens follow what changed while it was up, and the
    /// other devices' offer comes up. Under that offer they stay as they are, as they do for another device's change.
    /// A window that showed the welcome for want of accounts shows the mail of those added meanwhile.
    func settingsWindowClosed() {
        if case .welcome = screen, !model.accounts.isEmpty {
            showMailbox()
        } else if let built = uncoveredMail {
            followSettings(builtFrom: built)
        } else {
            return
        }
        offerSharedAccounts()
    }

    /// The reader changed something in the open Settings window: the mail screens follow at once, and the other
    /// devices' offer waits for it to close. With the last account gone they stay until it closes, so an account
    /// added back meanwhile finds them where they were.
    func settingsWindowChanged() {
        guard let built = uncoveredMail, !model.accounts.isEmpty else { return }
        followSettings(builtFrom: built)
    }

    /// Rebuilds the uncovered mail screens where the reader is when what they were `built` from has changed since
    /// (D9), or shows the welcome once the last account is gone.
    func followSettings(builtFrom built: Appearance) {
        if model.accounts.isEmpty {
            showWelcome()
        } else if Appearance(model) != built {
            showMailbox()
        }
    }
}

/// What the mail screens are built from that Settings can change, as the app holds it now.
typealias Appearance = MailScreenChoices

extension MailScreenChoices {
    init(_ model: AppModel) {
        self.init(
            accounts: model.accounts, unsortedInboxAccounts: Preferences.unsortedInboxAccounts,
            rowDisplay: Preferences.rowDisplay, theme: Preferences.combinedTheme)
    }
}
