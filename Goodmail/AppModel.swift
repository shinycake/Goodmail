import Foundation
import GmailProvider
import MailCore
import MailStore

/// The composition root, shared by every window: the database, the accounts, and each account's sync engine.
final class AppModel {
    let database: MailDatabase
    private(set) var accounts: [Account]
    private var engines: [AccountID: SyncEngine] = [:]

    init(database: MailDatabase) throws {
        self.database = database
        accounts = try database.accounts()
    }

    /// The shared container's database, so the extensions see the same mail (ADR-002).
    static func openShared() throws -> AppModel {
        // Unsigned simulator builds have no App Group.
        let directory = SharedContainer.directoryURL ?? URL.applicationSupportDirectory
        return try AppModel(database: MailDatabase(url: directory.appending(path: "Mail/mail.sqlite")))
    }

    /// Signs in with Google and adds the account, or re-authenticates it if it's already here.
    /// Returns `false` if the user cancelled.
    func addGmailAccount(using web: WebAuthentication) async throws -> Bool {
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        let url = GoogleOAuth.authorizationURL(pkce: pkce, state: state)
        guard let redirect = try await web.authenticate(url: url, callbackScheme: GmailConfiguration.redirectScheme)
        else { return false }

        let code = try GoogleOAuth.code(fromRedirect: redirect, expectedState: state)
        let existing = accounts
        let (session, email) = try await GmailSession.signIn(code: code, pkce: pkce) { email in
            existing.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }?.id ?? .generate()
        }
        engines[session.accountID] = engine(for: session)
        if !accounts.contains(where: { $0.id == session.accountID }) {
            let account = Account(
                id: session.accountID,
                email: email,
                color: AccountColor.next(after: accounts.map(\.color))
            )
            try database.save(account)
            accounts.append(account)
        }
        try await syncAll()
        return true
    }

    /// Syncs every account at once. Each engine coalesces overlapping calls, so this is safe to call often.
    func syncAll() async throws {
        let engines = accounts.map { engine(for: $0.id) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for engine in engines {
                group.addTask { try await engine.sync() }
            }
            try await group.waitForAll()
        }
    }

    private func engine(for id: AccountID) -> SyncEngine {
        if let engine = engines[id] { return engine }
        let engine = engine(for: GmailSession(accountID: id))
        engines[id] = engine
        return engine
    }

    private func engine(for session: GmailSession) -> SyncEngine {
        SyncEngine(accountID: session.accountID, provider: GmailClient(session: session), store: database)
    }
}
