import IMAPProvider
import MailCore
import MailUI
import OSLog

/// Signing an account in again after its service turned the stored sign-in down. The new sign-in keeps the account
/// and its mail, and its first sync clears the problem from the mailbox lists.
extension AccountSignIn {
    /// Each service's own way back in: the web sign-in, starting at the account's address, or its password again.
    func signIn(againTo account: Account) async {
        guard let web else { return }
        do {
            switch account.service {
            case .gmail: _ = try await model.addGmailAccount(using: web, loginHint: account.email)
            case .outlook: _ = try await model.addOutlookAccount(using: web, loginHint: account.email)
            case .icloud: _ = await signInToICloud(email: account.email)
            case .imap: await updatePassword(of: account)
            }
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "accounts")
                .error("Signing an account in again failed: \(error, privacy: .private)")
        }
    }

    /// Asks for the new password and checks it with the servers the account already has. An account whose login
    /// left the Keychain has no servers to keep, so it is set up again from the start.
    private func updatePassword(of account: Account) async {
        guard let login = try? IMAPSignIn(secrets: Keychain.signIns()).login(for: account.id) else {
            _ = await signInToOtherAccount()
            return
        }
        _ = await presentSignIn { [model] finished in
            UpdatePasswordScreen.make(
                email: account.email,
                update: { password in
                    do {
                        try await model.addIMAPAccount(
                            email: account.email, name: account.name, settings: login.settings, password: password)
                    } catch IMAPSignIn.Failure.refused {
                        throw UpdatePasswordFailure.wrongPassword
                    }
                },
                finished: finished)
        }
    }
}
