import Foundation
import MailCore

extension AccountProblemNotice {
    /// A short name for the problem, for the toolbar.
    var title: String {
        switch problem {
        case .signInRejected:
            String(
                localized: "Sign-In Needed", table: "Health", bundle: .module,
                comment: "Mailbox toolbar status: an account's service turned down its sign-in")
        case .cantSync:
            String(
                localized: "Can’t Sync", table: "Health", bundle: .module,
                comment: "Mailbox toolbar status: an account has failed to sync for a while")
        }
    }

    /// What went wrong and what fixes it, naming the account.
    var message: String {
        let email = account.email
        return switch (problem, account.service) {
        case (.signInRejected, .gmail), (.signInRejected, .outlook):
            String(
                localized: "\(account.service.displayName) needs \(email) to sign in again before it gets new mail.",
                table: "Health", bundle: .module,
                comment: "An OAuth service (Gmail, Outlook) revoked the account's sign-in; with the service and address"
            )
        case (.signInRejected, .icloud):
            String(
                localized:
                    "iCloud no longer accepts the app-specific password for \(email). It may have been revoked.",
                table: "Health", bundle: .module, comment: "iCloud turned down the account's stored password")
        case (.signInRejected, .imap):
            String(
                localized: "The mail server no longer accepts the password for \(email). It may have been changed.",
                table: "Health", bundle: .module, comment: "An IMAP server turned down the account's stored password")
        case (.cantSync(let reason), _):
            String(
                localized: "\(email) hasn’t synced for a while. \(reason.message)", table: "Health", bundle: .module,
                comment: "An account has failed to sync for minutes; then why, as a sentence")
        }
    }

    /// The button that fixes it.
    var fixTitle: String {
        switch (problem, account.service) {
        case (.signInRejected, .gmail), (.signInRejected, .outlook):
            String(
                localized: "Sign In Again", table: "Health", bundle: .module,
                comment: "Button: opens the service's sign-in page for the account")
        case (.signInRejected, .icloud), (.signInRejected, .imap):
            String(
                localized: "Update Password", table: "Health", bundle: .module,
                comment: "Button: asks for the account's new password")
        case (.cantSync, _):
            String(
                localized: "Try Again", table: "Health", bundle: .module, comment: "Button: syncs the accounts now")
        }
    }
}

extension [AccountProblemNotice] {
    /// The toolbar's status: the one problem's name with its account, or a count of the accounts that have one.
    var summary: (title: String, subtitle: String?)? {
        switch count {
        case 0: nil
        case 1: (self[0].title, self[0].account.email)
        default:
            (
                String(
                    localized: "Accounts Need Attention", table: "Health", bundle: .module,
                    comment: "Mailbox toolbar status: more than one account has a sync problem"), nil
            )
        }
    }
}
