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
    private let providers: Providers
    private var engines: [AccountID: SyncEngine] = [:]
    private var prefetchers: [AccountID: BodyPrefetcher] = [:]
    private let path = PathMonitor()
    /// Where opened attachments are kept; they count toward the cache cap with the bodies.
    let attachmentsDirectory = URL.cachesDirectory.appending(path: "Attachments", directoryHint: .isDirectory)
    private let outboxes: Outboxes
    private let senders: Senders

    init(database: MailDatabase) throws {
        self.database = database
        accounts = try database.accounts()
        let providers = Providers(database: database)
        self.providers = providers
        let outboxes = Outboxes { id in
            Outbox(accountID: id, provider: try providers.provider(for: id), store: database)
        }
        self.outboxes = outboxes
        let senders = Senders { id in
            Sender(
                accountID: id, provider: try providers.provider(for: id), store: database)
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
        let url = OAuthClient.gmail.authorizationURL(pkce: pkce, state: state)
        guard let redirect = try await web.authenticate(url: url, callbackScheme: OAuthClient.gmail.redirectScheme)
        else { return false }

        let code = try OAuthClient.code(fromRedirect: redirect, expectedState: state)
        let existing = accounts
        let (session, email) = try await OAuthSession.signIn(
            client: .gmail, code: code, pkce: pkce,
            accountID: { email in
                existing.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }?.id ?? .generate()
            },
            keychain: Keychain())
        providers.use(GmailClient(session: session), for: session.accountID)
        engines[session.accountID] = nil
        if !accounts.contains(where: { $0.id == session.accountID }) {
            let account = Account(
                id: session.accountID,
                email: email,
                color: AccountColor.next(after: accounts.map(\.color)),
                service: .gmail
            )
            try database.save(account)
            accounts.append(account)
        }
        try await syncAll()
        return true
    }

    /// Signs the account out and takes it and its mail off the device. Nothing changes at its service.
    func removeAccount(_ id: AccountID) async throws {
        if let account = accounts.first(where: { $0.id == id }) { try? await Providers.signOut(account) }
        providers.forget(id)
        engines[id] = nil
        await prefetchers[id]?.cancel()
        prefetchers[id] = nil
        await outboxes.forget(id)
        senders.forget(id)
        try database.removeAccount(id)
        try? FileManager.default.removeItem(at: attachmentsDirectory.appending(path: id.rawValue))
        accounts.removeAll { $0.id == id }
    }

    /// Stores the account's new name or color.
    func update(_ account: Account) throws {
        try database.update(account)
        accounts = accounts.map { $0.id == account.id ? account : $0 }
    }

    /// Sends queued actions, then syncs, every account at once. Each engine coalesces overlapping calls, so this is
    /// safe to call often. With `prefetch`, each account then starts fetching bodies in the background (ADR-007);
    /// a background refresh leaves that to the next time the app is open.
    func syncAll(prefetch: Bool = true) async throws {
        let engines = try accounts.map { try engine(for: $0.id) }
        let prefetchers = try accounts.map { try prefetcher(for: $0.id) }
        let outboxes = outboxes
        // Snoozed threads whose time came, queued before the replay below so the server hears of them now.
        try commands.wakeSnoozed()
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
        if prefetch { for prefetcher in prefetchers { await prefetcher.start() } }
        await trimCache()
    }

    /// Stops prefetching, as when the app leaves the foreground. The next sync picks up where it left off.
    func cancelPrefetch() async {
        for prefetcher in prefetchers.values { await prefetcher.cancel() }
    }

    /// Evicts the least recently read bodies and attachments when the cache is over its cap (ADR-007). Off the
    /// main thread: it scans the attachments folder.
    private func trimCache() async {
        await Self.trim(database, attachments: attachmentsDirectory)
    }

    private nonisolated static func trim(_ database: MailDatabase, attachments: URL) async {
        await Task.detached(priority: .utility) {
            do {
                try database.trimCache(attachments: attachments)
            } catch {
                Logger(subsystem: "com.idanbirman.goodmail", category: "cache")
                    .error("Couldn't trim the cache: \(error, privacy: .public)")
            }
        }.value
    }

    /// Fetches the next older page of `mailbox` in each account it covers. Returns whether any may have more.
    func loadOlder(_ mailbox: Mailbox) async throws -> Bool {
        let engines = try accounts.map { try engine(for: $0.id) }
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            for engine in engines {
                group.addTask { try await engine.backfill(mailbox) }
            }
            var mayHaveMore = false
            for try await more in group { mayHaveMore = mayHaveMore || more }
            return mayHaveMore
        }
    }

    /// Every account's provider matches for `text`, stored: the first page, or after `page`, the next page of each
    /// account it says has more. Accounts that fail are left out, unless all of them do; a failed next page keeps its
    /// token, so the next approach to the end asks again.
    func search(_ text: String, after page: SearchPage? = nil) async throws -> SearchPage {
        // Each account to ask, with the page token to ask from: none for the first page.
        let tokens: [AccountID: String?] =
            page?.next.mapValues(Optional.some) ?? Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, nil) })
        let requests = try tokens.map { (engine: try engine(for: $0.key), token: $0.value) }
        let results = await withTaskGroup(of: (AccountID, Result<SearchPage, any Error>).self) { group in
            for (engine, token) in requests {
                group.addTask { (engine.accountID, await Result { try await engine.search(text, pageToken: token) }) }
            }
            var results: [(AccountID, Result<SearchPage, any Error>)] = []
            for await result in group { results.append(result) }
            return results
        }
        var found = SearchPage()
        var failures: [any Error] = []
        for (account, result) in results {
            do {
                let page = try result.get()
                found.ids += page.ids
                found.next.merge(page.next) { first, _ in first }
            } catch {
                failures.append(error)
                if let token = tokens[account] ?? nil { found.next[account] = token }
            }
        }
        if failures.count == results.count, let failure = failures.first { throw failure }
        return found
    }

    /// Fetches a thread's messages with their bodies into the store, where the thread view reads them.
    func loadMessages(of thread: ThreadSummary.ID) async throws {
        let fetchedAt = Date.now
        let messages = try await providers.provider(for: thread.accountID).messages(inThread: thread.threadID)
        try database.save(messages, inThread: thread, fetchedAt: fetchedAt)
    }

    /// The thread's cached messages, which the reader follows. Opening a thread marks its bodies as read.
    func messages(inThread id: ThreadSummary.ID) -> AsyncThrowingStream<[Message], any Error> {
        try? database.touchMessages(inThread: id)
        return database.messages(inThread: id)
    }

    func attachmentData(_ attachment: Attachment, in message: Message.ID) async throws -> Data {
        try await providers.provider(for: message.accountID).data(for: attachment, in: message)
    }

    private func prefetcher(for id: AccountID) throws -> BodyPrefetcher {
        if let prefetcher = prefetchers[id] { return prefetcher }
        let (database, attachments) = (database, attachmentsDirectory)
        let prefetcher = BodyPrefetcher(
            accountID: id, provider: try providers.provider(for: id), store: database, path: path,
            didFinish: { await Self.trim(database, attachments: attachments) })
        prefetchers[id] = prefetcher
        return prefetcher
    }

    private func engine(for id: AccountID) throws -> SyncEngine {
        if let engine = engines[id] { return engine }
        let engine = SyncEngine(accountID: id, provider: try providers.provider(for: id), store: database)
        engines[id] = engine
        return engine
    }
}

/// One outbox per account, made on first use. Failed drains stay queued until the next flush.
actor Outboxes {
    private let make: @Sendable (AccountID) throws -> Outbox
    private var outboxes: [AccountID: Outbox] = [:]

    init(make: @escaping @Sendable (AccountID) throws -> Outbox) {
        self.make = make
    }

    func forget(_ id: AccountID) {
        outboxes[id] = nil
    }

    func flush(_ id: AccountID) async {
        do {
            let outbox = try outboxes[id] ?? make(id)
            outboxes[id] = outbox
            try await outbox.flush()
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "outbox")
                .error("Replay stopped: \(error, privacy: .public)")
        }
    }
}

/// One sender per account. A message is sent once its undo window closes, with background time asked for so
/// leaving the app in that window doesn't hold it back. One scheduled further ahead is left to the next sync after
/// its time: the foreground sync while the app is open, or a background refresh.
final class Senders {
    /// The longest wait held in background time; the longest undo window is 30 seconds.
    static let longestHeldWait: TimeInterval = 60

    var onSent: ((AccountID, [Draft]) async -> Void)?
    private let make: (AccountID) throws -> Sender
    private var senders: [AccountID: Sender] = [:]

    init(make: @escaping (AccountID) throws -> Sender) {
        self.make = make
    }

    func forget(_ id: AccountID) {
        senders[id] = nil
    }

    func deliver(_ id: AccountID, at date: Date) async {
        guard date.timeIntervalSinceNow <= Self.longestHeldWait else { return }
        let application = UIApplication.shared
        let background = application.beginBackgroundTask(withName: "Send")
        defer { if background != .invalid { application.endBackgroundTask(background) } }
        let wait = date.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        let sender: Sender
        do {
            sender = try senders[id] ?? make(id)
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "send")
                .error("No sender: \(error, privacy: .public)")
            return
        }
        senders[id] = sender
        let sent = await sender.flush()
        if !sent.isEmpty { await onSent?(id, sent) }
    }
}
