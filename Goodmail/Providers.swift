import GmailProvider
import IMAPProvider
import MailClients
import MailCore
import MailStore
import OutlookProvider

/// Each account's session (`AccountSession`), made from its stored sign-in on first use and shared by everything that
/// talks to it: sync, prefetch and the watch, and the outbox and sending, which read its provider as each drain
/// begins. The one place that knows which provider serves
/// which service, and the one that replaces an account's session when its sign-in changes.
nonisolated final class Providers: Sendable {
    enum Failure: Error {
        /// No stored account has this ID, as when it was removed while work for it was queued.
        case unknownAccount
    }

    private let sessions: AccountSessions<AccountSession>
    /// Makes the session that works on a provider.
    private let makeSession: @Sendable (AccountID, any MailProvider) -> AccountSession

    /// `accounts` are the stored accounts as the app model follows them, which sessions are made for, so making one
    /// reads nothing from the database on whichever actor asks first, the main actor among them (ADR-043). `index`
    /// keeps the thread of each message for the providers whose changes name messages.
    init(
        accounts: FollowedValue<StoredAccounts>, index: MailDatabase,
        makeSession: @escaping @Sendable (AccountID, any MailProvider) -> AccountSession
    ) {
        self.makeSession = makeSession
        sessions = AccountSessions { id in
            guard let account = accounts.latest.accounts.first(where: { $0.id == id }) else {
                throw Failure.unknownAccount
            }
            return makeSession(id, try MailClients.client(for: account, index: index))
        }
    }

    func session(for id: AccountID) throws -> AccountSession {
        do {
            return try sessions.session(for: id)
        } catch AccountSessions<AccountSession>.Failure.removed {
            // Being removed is no account as far as the work queued for it goes.
            throw Failure.unknownAccount
        }
    }

    /// The account's provider, its session made off the caller's actor if it isn't yet: making one reads the
    /// Keychain.
    @concurrent func provider(madeFor id: AccountID) async throws -> any MailProvider {
        try provider(for: id)
    }

    func provider(for id: AccountID) throws -> any MailProvider {
        try session(for: id).provider
    }

    /// The sessions made so far, as for stopping their prefetch. Reading it makes none.
    var live: [AccountID: AccountSession] { sessions.live }

    /// Serves the account with `provider` from now on, as after a sign-in whose session already holds a fresh token.
    func use(_ provider: any MailProvider, for id: AccountID) async {
        await sessions.replace(id, with: makeSession(id, provider))
    }

    /// Serves the account from its stored sign-in, read afresh on next use, as after a new password or server, or
    /// once it's added back.
    func reload(_ id: AccountID) async {
        await sessions.replace(id)
    }

    /// Ends the account's session, so nothing refreshes or writes its sign-in while the account goes.
    func remove(_ id: AccountID) async {
        await sessions.remove(id)
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
}
