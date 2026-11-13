import GmailProvider
import MailCore
import MailStore
import Synchronization

/// Each account's provider, made for the account's service on first use and shared by everything that talks to it:
/// sync, the outbox, sending and prefetch. The one place that knows which provider serves which service.
final class Providers: Sendable {
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
        let provider = Self.make(for: account)
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

    /// Forgets the account's credentials on the device. Nothing changes at the service.
    static func signOut(_ account: Account) throws {
        switch account.service {
        case .gmail: try GmailSession(accountID: account.id, keychain: Keychain()).signOut()
        }
    }

    private static func make(for account: Account) -> any MailProvider {
        switch account.service {
        case .gmail: GmailClient(session: GmailSession(accountID: account.id, keychain: Keychain()))
        }
    }
}
