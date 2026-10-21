import Foundation
import GmailProvider
import MailCore
import MailStore
import OSLog

/// The composition root, shared by every window: the database, the accounts, each account's sync engine, and the
/// commands that change mail.
final class AppModel {
    let database: MailDatabase
    let commands: MailCommands
    private(set) var accounts: [Account]
    private var clients: [AccountID: GmailClient] = [:]
    private var engines: [AccountID: SyncEngine] = [:]
    private let outboxes: Outboxes

    init(database: MailDatabase) throws {
        self.database = database
        accounts = try database.accounts()
        let outboxes = Outboxes { id in
            Outbox(accountID: id, provider: GmailClient(session: GmailSession(accountID: id)), store: database)
        }
        self.outboxes = outboxes
        commands = MailCommands(store: database, replay: { id in Task { await outboxes.flush(id) } })
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
        clients[session.accountID] = GmailClient(session: session)
        engines[session.accountID] = nil
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

    /// Sends queued actions, then syncs, every account at once. Each engine coalesces overlapping calls, so this is
    /// safe to call often.
    func syncAll() async throws {
        let engines = accounts.map { engine(for: $0.id) }
        let outboxes = outboxes
        try await withThrowingTaskGroup(of: Void.self) { group in
            for engine in engines {
                group.addTask {
                    // Replay first, so the sync reads the server after the reader's actions.
                    await outboxes.flush(engine.accountID)
                    try await engine.sync()
                }
            }
            try await group.waitForAll()
        }
    }

    /// Fetches the next older page of `label` in every account. Returns whether any account may have more.
    func loadOlder(label: String) async throws -> Bool {
        let engines = accounts.map { engine(for: $0.id) }
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            for engine in engines {
                group.addTask { try await engine.backfill(label: label) }
            }
            var mayHaveMore = false
            for try await more in group { mayHaveMore = mayHaveMore || more }
            return mayHaveMore
        }
    }

    /// Fetches a thread's messages with their bodies into the store, where the thread view reads them.
    func loadMessages(of thread: ThreadSummary.ID) async throws {
        let fetchedAt = Date.now
        let messages = try await client(for: thread.accountID).messages(inThread: thread.threadID)
        try database.save(messages, inThread: thread, fetchedAt: fetchedAt)
    }

    func attachmentData(_ attachment: Attachment, in message: Message.ID) async throws -> Data {
        try await client(for: message.accountID).data(for: attachment, in: message)
    }

    private func client(for id: AccountID) -> GmailClient {
        if let client = clients[id] { return client }
        let client = GmailClient(session: GmailSession(accountID: id))
        clients[id] = client
        return client
    }

    private func engine(for id: AccountID) -> SyncEngine {
        if let engine = engines[id] { return engine }
        let engine = SyncEngine(accountID: id, provider: client(for: id), store: database)
        engines[id] = engine
        return engine
    }
}

/// One outbox per account, made on first use. Failed drains stay queued until the next flush.
actor Outboxes {
    private let make: @Sendable (AccountID) -> Outbox
    private var outboxes: [AccountID: Outbox] = [:]

    init(make: @escaping @Sendable (AccountID) -> Outbox) {
        self.make = make
    }

    func flush(_ id: AccountID) async {
        let outbox = outboxes[id] ?? make(id)
        outboxes[id] = outbox
        do {
            try await outbox.flush()
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "outbox")
                .error("Replay stopped: \(error, privacy: .public)")
        }
    }
}
