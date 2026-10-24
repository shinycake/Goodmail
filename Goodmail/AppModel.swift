import Foundation
import GmailProvider
import MailCore
import MailStore
import OSLog
import UIKit

/// The composition root, shared by every window: the database, the accounts, each account's sync engine, and the
/// commands that change mail.
final class AppModel {
    let database: MailDatabase
    let commands: MailCommands
    private(set) var accounts: [Account]
    private var clients: [AccountID: GmailClient] = [:]
    private var engines: [AccountID: SyncEngine] = [:]
    private let outboxes: Outboxes
    private let senders: Senders

    init(database: MailDatabase) throws {
        self.database = database
        accounts = try database.accounts()
        let outboxes = Outboxes { id in
            Outbox(accountID: id, provider: GmailClient(session: GmailSession(accountID: id)), store: database)
        }
        self.outboxes = outboxes
        let senders = Senders { id in
            let email = (try? database.accounts().first { $0.id == id }?.email) ?? ""
            return Sender(
                accountID: id, provider: GmailClient(session: GmailSession(accountID: id)), store: database,
                from: Contact(name: nil, address: email))
        }
        self.senders = senders
        commands = MailCommands(
            store: database,
            replay: { id in Task { await outboxes.flush(id) } },
            deliver: { id, date in Task { await senders.deliver(id, at: date) } })
        // A sent message lands in its thread on the server; fetch it so the list and the reader show it there.
        senders.onSent = { [weak self] id, sent in
            guard let self else { return }
            try? await engine(for: id).sync()
            for threadID in Set(sent.compactMap(\.threadID)) {
                try? await loadMessages(of: ThreadSummary.ID(accountID: id, threadID: threadID))
            }
        }
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

    /// Signs the account out and takes it and its mail off the device. Nothing changes in Gmail.
    func removeAccount(_ id: AccountID) async throws {
        try? await GmailSession(accountID: id).signOut()
        clients[id] = nil
        engines[id] = nil
        await outboxes.forget(id)
        senders.forget(id)
        try database.removeAccount(id)
        accounts.removeAll { $0.id == id }
    }

    /// Sends queued actions, then syncs, every account at once. Each engine coalesces overlapping calls, so this is
    /// safe to call often.
    func syncAll() async throws {
        let engines = accounts.map { engine(for: $0.id) }
        let outboxes = outboxes
        // Messages whose undo window closed while the app was away.
        for account in accounts { await senders.deliver(account.id, at: .now) }
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

    /// Fetches the next older page of `mailbox` in each account it covers. Returns whether any may have more.
    func loadOlder(_ mailbox: Mailbox) async throws -> Bool {
        let engines = accounts.map { engine(for: $0.id) }
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            for engine in engines {
                group.addTask { try await engine.backfill(mailbox) }
            }
            var mayHaveMore = false
            for try await more in group { mayHaveMore = mayHaveMore || more }
            return mayHaveMore
        }
    }

    /// Every account's provider matches for `text`, stored. Accounts that fail are left out, unless all of them do.
    func search(_ text: String) async throws -> [ThreadSummary.ID] {
        let engines = accounts.map { engine(for: $0.id) }
        let results = await withTaskGroup(of: Result<[ThreadSummary.ID], any Error>.self) { group in
            for engine in engines {
                group.addTask { await Result { try await engine.search(text) } }
            }
            var results: [Result<[ThreadSummary.ID], any Error>] = []
            for await result in group { results.append(result) }
            return results
        }
        let found = results.compactMap { try? $0.get() }
        if found.isEmpty, let failure = results.first { _ = try failure.get() }
        return found.flatMap(\.self)
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

    func forget(_ id: AccountID) {
        outboxes[id] = nil
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

/// One sender per account. Each queued message is sent once its undo window closes, with background time asked
/// for so leaving the app in that window doesn't hold it back.
final class Senders {
    var onSent: ((AccountID, [Draft]) async -> Void)?
    private let make: (AccountID) -> Sender
    private var senders: [AccountID: Sender] = [:]

    init(make: @escaping (AccountID) -> Sender) {
        self.make = make
    }

    func forget(_ id: AccountID) {
        senders[id] = nil
    }

    func deliver(_ id: AccountID, at date: Date) async {
        let application = UIApplication.shared
        let background = application.beginBackgroundTask(withName: "Send")
        defer { if background != .invalid { application.endBackgroundTask(background) } }
        let wait = date.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        let sender = senders[id] ?? make(id)
        senders[id] = sender
        let sent = await sender.flush()
        if !sent.isEmpty { await onSent?(id, sent) }
    }
}
