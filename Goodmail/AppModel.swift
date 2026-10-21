import Foundation
import GmailProvider
import MailCore
import MailStore

/// The composition root, shared by every window: the database, the accounts and their Gmail sessions.
final class AppModel {
    let database: MailDatabase
    private(set) var accounts: [Account]
    private var sessions: [AccountID: GmailSession] = [:]

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
        sessions[session.accountID] = session
        if !accounts.contains(where: { $0.id == session.accountID }) {
            let account = Account(
                id: session.accountID,
                email: email,
                color: AccountColor.next(after: accounts.map(\.color))
            )
            try database.save(account)
            accounts.append(account)
        }
        try await refreshInbox()
        return true
    }

    /// Fetches the newest Inbox page of every account into the store.
    func refreshInbox() async throws {
        let clients = accounts.map { GmailClient(session: session(for: $0.id)) }
        try await withThrowingTaskGroup(of: [ThreadSummary].self) { group in
            for client in clients {
                group.addTask { try await client.inboxThreads() }
            }
            for try await threads in group {
                try database.upsert(threads)
            }
        }
    }

    private func session(for id: AccountID) -> GmailSession {
        if let session = sessions[id] { return session }
        let session = GmailSession(accountID: id)
        sessions[id] = session
        return session
    }
}
