import GmailProvider
import IMAPProvider
import MailClients
import MailCore
import MailStore
import OutlookProvider
import Synchronization

/// Each account's provider, made for the account's service on first use and shared by everything that talks to it:
/// sync, the outbox, sending and prefetch. The one place that knows which provider serves which service.
nonisolated final class Providers: Sendable {
    enum Failure: Error {
        /// No stored account has this ID, as when it was removed while work for it was queued.
        case unknownAccount
    }

    private let database: MailDatabase
    private let made = Mutex<[AccountID: any MailProvider]>([:])

    init(database: MailDatabase) {
        self.database = database
    }

    func provider(for id: AccountID) throws -> any MailProvider {
        if let provider = made.withLock({ $0[id] }) { return provider }
        guard let account = try database.accounts().first(where: { $0.id == id }) else { throw Failure.unknownAccount }
        let provider = try make(for: account)
        return made.withLock { made in
            if let existing = made[id] { return existing }
            made[id] = provider
            return provider
        }
    }

    /// Serves the account with `provider` from now on, as after a sign-in whose session already holds a fresh token.
    func use(_ provider: any MailProvider, for id: AccountID) {
        made.withLock { $0[id] = provider }
    }

    func forget(_ id: AccountID) {
        made.withLock { $0[id] = nil }
    }

    /// How the account's service tells the relay about new mail. Gmail and Outlook push through their own APIs, so
    /// their provider is the source; for IMAP accounts the relay watches the Inbox with the account's login.
    func pushSource(for account: Account) throws -> any PushSource {
        switch account.service {
        case .gmail, .outlook:
            guard let source = try provider(for: account.id) as? any PushSource else {
                throw Failure.unknownAccount
            }
            return source
        case .icloud:
            return IMAPPushSource(
                accountID: account.id, settings: .icloud(email: account.email),
                password: try ICloudSignIn(secrets: Keychain.signIns()).appPassword(for: account.id))
        case .imap:
            let login = try IMAPSignIn(secrets: Keychain.signIns()).login(for: account.id)
            return IMAPPushSource(accountID: account.id, settings: login.settings, password: login.password)
        }
    }

    /// Forgets the account's credentials in `secrets`: this device's alone, or with the copy the reader's other
    /// devices share. Nothing changes at the service.
    static func signOut(_ account: Account, from secrets: any SecretStore) throws {
        try secrets.remove(signInKey(account.id, account.service))
    }

    /// Where the account's sign-in is stored, which depends on its service.
    static func signInKey(_ id: AccountID, _ service: MailService) -> String {
        switch service {
        case .gmail: OAuthClient.gmail.refreshTokenKey(id)
        case .icloud: ICloudSignIn.key(id)
        case .outlook: OAuthClient.outlook.refreshTokenKey(id)
        case .imap: IMAPSignIn.key(id)
        }
    }

    private func make(for account: Account) throws -> any MailProvider {
        try MailClients.client(for: account, index: database)
    }
}
