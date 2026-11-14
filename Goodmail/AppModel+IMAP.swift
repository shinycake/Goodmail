import IMAPProvider
import MailCore

/// Accounts on any IMAP and SMTP server.
extension AppModel {
    /// Logs in to both of `settings`' servers, then adds the account, or updates the login of the one already here.
    /// Throws `IMAPSignIn.Failure` when a server refuses or can't be reached.
    func addIMAPAccount(email: String, name: String?, settings: MailServerSettings, password: String) async throws {
        try await addPasswordAccount(.imap, email: email, name: name) { _, id in
            try await IMAPSignIn(secrets: Keychain()).signIn(settings: settings, password: password, accountID: id)
        }
    }

}
