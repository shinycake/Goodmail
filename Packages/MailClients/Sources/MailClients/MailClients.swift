import GmailProvider
import IMAPProvider
public import MailCore
import OutlookProvider

/// Builds an account's mail client from the sign-in this device keeps in the shared Keychain, the same way in the
/// app, the notification extension and the Share extension.
public enum MailClients {
    #if canImport(Security) && canImport(Network)
        /// The client for `account`. `index` is the shared database, which Outlook and IMAP use to find the
        /// conversation a message belongs to. Throws when the account's login isn't in the Keychain.
        public static func client(for account: Account, index: any MessageIndexStore) throws -> any MailProvider {
            switch account.service {
            case .gmail:
                GmailClient(session: OAuthSession(accountID: account.id, client: .gmail, keychain: Keychain.signIns()))
            case .icloud:
                IMAPClient(
                    accountID: account.id, settings: .icloud(email: account.email),
                    password: try ICloudSignIn(secrets: Keychain.signIns()).appPassword(for: account.id), index: index)
            case .outlook:
                OutlookClient(
                    session: OAuthSession(accountID: account.id, client: .outlook, keychain: Keychain.signIns()),
                    index: index)
            case .imap:
                IMAPClient(
                    accountID: account.id, login: try IMAPSignIn(secrets: Keychain.signIns()).login(for: account.id),
                    index: index)
            }
        }
    #endif
}
