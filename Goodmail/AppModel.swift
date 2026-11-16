import Foundation
import GmailProvider
import IMAPProvider
import MailCore
import MailStore
import MailUI
import OSLog
import OutlookProvider
import UIKit

/// The composition root, shared by every window: the database, the accounts, each account's sync engine, and the
/// commands that change mail.
final class AppModel {
    let database: MailDatabase
    let commands: MailCommands
    private(set) var accounts: [Account]
    let providers: Providers
    private var engines: [AccountID: SyncEngine] = [:]
    private var prefetchers: [AccountID: BodyPrefetcher] = [:]
    private let path = PathMonitor()
    /// Where opened attachments are kept; they count toward the cache cap with the bodies.
    let attachmentsDirectory = URL.cachesDirectory.appending(path: "Attachments", directoryHint: .isDirectory)
    let outboxes: Outboxes
    /// How each account's syncs are going, for the mailbox lists to tell the reader of a problem.
    let health = AccountHealthBoard()
    /// Senders' photos and logos for the mail screens.
    let senderPictures: SenderPictures
    private let senders: Senders
    /// Keeps each account's push subscription current; `nil` when the build names no push relay.
    let pushRegistrar: PushRegistrar?
    /// This device's APNs token, once iOS hands it over.
    var pushDevice: DeviceToken?
    /// Runs after an account is added, so alerts can be asked for and set up.
    var didAddAccount: (() -> Void)?
    /// Told after the stored mail changes in bulk, so the system's copies (Spotlight) can follow.
    var didChange: (@Sendable (MailChange) async -> Void)?

    nonisolated enum MailChange: Sendable {
        /// A sync finished, of every account or of one whose server reported a change.
        case synced
        /// An account and its mail left the device.
        case accountRemoved
    }

    /// `pushRelay` is where accounts subscribe to push; `nil` keeps alerts off, as in synthetic mailboxes.
    init(database: MailDatabase, pushRelay: URL? = PushConfiguration.relayURL) throws {
        self.database = database
        senderPictures = .cached(with: database)
        accounts = try database.accounts()
        pushRegistrar = pushRelay.map {
            PushRegistrar(relay: PushRelayClient(baseURL: $0), store: database)
        }
        let providers = Providers(database: database)
        self.providers = providers
        let outboxes = Outboxes { id in
            Outbox(accountID: id, provider: try providers.provider(for: id), store: database)
        }
        self.outboxes = outboxes
        let uploads = URL.applicationSupportDirectory.appending(path: "Uploads", directoryHint: .isDirectory)
        let senders = Senders { id, transport in
            Sender(
                accountID: id, provider: try providers.provider(for: id), store: database, transport: transport,
                uploads: uploads)
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

    /// iOS launched or woke the app to hand over the outcomes of uploads that finished while it was away.
    func handleBackgroundUploadEvents(_ completion: @escaping @MainActor () -> Void) {
        senders.uploads.handleEvents(completion: completion)
    }

    /// The shared container's database, so the extensions see the same mail (ADR-002).
    static func openShared() async throws -> AppModel {
        try AppModel(database: await openSharedDatabase())
    }

    /// Off the main actor: opening migrates the database and fills in what older builds left out, which can take a
    /// while after an update.
    @concurrent private nonisolated static func openSharedDatabase() async throws -> MailDatabase {
        // Unsigned simulator builds have no App Group.
        let directory = SharedContainer.directoryURL ?? URL.applicationSupportDirectory
        return try MailDatabase(url: directory.appending(path: "Mail/mail.sqlite"))
    }

    /// Signs in with Google and adds the account, or re-authenticates it if it's already here. `loginHint` is the
    /// address Google's page starts with, as when signing an account in again. Returns `false` if the user cancelled.
    func addGmailAccount(using web: WebAuthentication, loginHint: String? = nil) async throws -> Bool {
        try await addAccount(.gmail, signingInWith: .gmail, using: web, loginHint: loginHint) {
            GmailClient(session: $0)
        }
    }

    /// Signs in with Microsoft and adds the Outlook account, or re-authenticates it if it's already here. `loginHint`
    /// is the address Microsoft's page starts with. Returns `false` if the user cancelled.
    func addOutlookAccount(using web: WebAuthentication, loginHint: String? = nil) async throws -> Bool {
        try await addAccount(.outlook, signingInWith: .outlook, using: web, loginHint: loginHint) { [database] in
            OutlookClient(session: $0, index: database)
        }
    }

    /// The web sign-in every OAuth service shares: the service's page, the code exchange, then the account, kept
    /// under the ID it already had when this address at this service is here.
    private func addAccount(
        _ service: MailService, signingInWith client: OAuthClient, using web: WebAuthentication,
        loginHint: String? = nil, provider: (OAuthSession) -> any MailProvider
    ) async throws -> Bool {
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        let url = client.authorizationURL(pkce: pkce, state: state, loginHint: loginHint)
        guard let redirect = try await web.authenticate(url: url, callbackScheme: client.redirectScheme)
        else { return false }

        let code = try OAuthClient.code(fromRedirect: redirect, expectedState: state)
        let existing = accounts.filter { $0.service == service }
        let (session, email) = try await OAuthSession.signIn(
            client: client, code: code, pkce: pkce,
            accountID: { email in
                existing.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }?.id ?? .generate()
            },
            keychain: Keychain())
        providers.use(provider(session), for: session.accountID)
        engines[session.accountID] = nil
        if !accounts.contains(where: { $0.id == session.accountID }) {
            let account = Account(
                id: session.accountID,
                email: email,
                color: AccountColor.next(after: accounts.map(\.color)),
                service: service
            )
            try await Self.store { [database] in try database.save(account) }
            accounts.append(account)
            didAddAccount?()
        }
        await syncAfterAdding()
        return true
    }

    /// Checks the app-specific password by logging in to iCloud, then adds the account, or updates the password of
    /// the one already here. Throws `ICloudSignIn.Failure.wrongPassword` when iCloud refuses it.
    func addICloudAccount(email: String, appPassword: String) async throws {
        try await addPasswordAccount(.icloud, email: email) { email, id in
            try await ICloudSignIn(secrets: Keychain()).signIn(email: email, appPassword: appPassword, accountID: id)
        }
    }

    /// The sign-in every password service shares: `signIn` checks and keeps the login under the account's ID, the
    /// one this address at this service already has when it's here. Then the account is added, with `name` to send
    /// under, or its new login is used.
    func addPasswordAccount(
        _ service: MailService, email typed: String, name: String? = nil,
        signIn: (_ email: String, _ id: AccountID) async throws -> Void
    ) async throws {
        let email = typed.trimmingCharacters(in: .whitespaces)
        let existing = accounts.first {
            $0.service == service && $0.email.caseInsensitiveCompare(email) == .orderedSame
        }
        let id = existing?.id ?? .generate()
        try await signIn(email, id)
        providers.forget(id)
        engines[id] = nil
        if existing == nil {
            let account = Account(
                id: id, email: email,
                color: AccountColor.next(after: accounts.map(\.color)), service: service, name: name)
            try await Self.store { [database] in try database.save(account) }
            accounts.append(account)
        }
        await syncAfterAdding()
    }

    /// Syncs every account once one was added. The account is already here, so a failed sync doesn't undo it or say
    /// the sign-in failed, least of all when it's another account that can't sync. The next sync tries again.
    private func syncAfterAdding() async {
        do {
            try await syncAll()
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
                .error("The sync after adding an account failed: \(error, privacy: .public)")
        }
    }

    /// Signs the account out and takes it and its mail off the device. Nothing changes at its service.
    func removeAccount(_ id: AccountID) async throws {
        // While the account can still prove its address to the relay.
        await unsubscribePush(id)
        if let account = accounts.first(where: { $0.id == id }) { try? await Providers.signOut(account) }
        providers.forget(id)
        engines[id] = nil
        await prefetchers[id]?.cancel()
        prefetchers[id] = nil
        await outboxes.forget(id)
        senders.forget(id)
        // Takes every thread and body of the account with it, which can be most of the database.
        try await Self.store { [database] in try database.removeAccount(id) }
        try? FileManager.default.removeItem(at: attachmentsDirectory.appending(path: id.rawValue))
        accounts.removeAll { $0.id == id }
        health.forget(id)
        await didChange?(.accountRemoved)
    }

    /// Stores the account's new name or color.
    func update(_ account: Account) async throws {
        try await Self.store { [database] in try database.update(account) }
        accounts = accounts.map { $0.id == account.id ? account : $0 }
    }

    /// Stores the order the reader put the accounts in, which every list of accounts follows.
    func reorderAccounts(_ order: [AccountID]) async throws {
        accounts = try await Self.offMain { [database] in
            try database.reorderAccounts(order)
            return try database.accounts()
        }
    }

    /// Sends queued actions, then syncs, every account at once, and tells `health` how each went. Each engine
    /// coalesces overlapping calls, so this is safe to call often. One account that fails doesn't stop the others;
    /// once all are done, the first failure is thrown. With `prefetch`, each account that synced then starts
    /// fetching bodies in the background (ADR-007); a background refresh leaves that to the next time the app is open.
    func syncAll(prefetch: Bool = true) async throws {
        // An account whose login is gone from the Keychain has no provider, which is its failure to sync.
        let engines = accounts.map { account in (account.id, Result { try engine(for: account.id) }) }
        let outboxes = outboxes
        // Snoozed threads whose time came, queued before the replay below so the server hears of them now.
        try await commands.wakeSnoozed()
        // Messages whose undo window closed while the app was away.
        for account in accounts { await senders.deliver(account.id, at: .now) }
        let outcomes = await withTaskGroup(of: (AccountID, Result<Void, any Error>).self) { group in
            for (id, engine) in engines {
                group.addTask {
                    let outcome = await Result {
                        let engine = try engine.get()
                        // Replay first, so the sync reads the server after the reader's actions.
                        await outboxes.flush(id)
                        try await engine.sync()
                    }
                    return (id, outcome)
                }
            }
            var outcomes: [AccountID: Result<Void, any Error>] = [:]
            for await (id, outcome) in group { outcomes[id] = outcome }
            return outcomes
        }
        for (id, outcome) in outcomes { health.record(outcome, for: id) }
        let synced = accounts.filter { if case .success = outcomes[$0.id] { true } else { false } }
        // With nothing new stored, the accounts, the cache and the system's copies (Spotlight) have nothing to follow.
        if !synced.isEmpty {
            // The sync reads each account's aliases, which the composer and replies take from `accounts`.
            let stored = try await Self.offMain { [database] in try database.accounts() }
            if stored != accounts { accounts = stored }
            await runRules(for: synced)
            if prefetch { for account in synced { await (try? prefetcher(for: account.id))?.start() } }
            await trimCache()
            await didChange?(.synced)
        }
        for account in accounts { if case .failure(let error) = outcomes[account.id] { throw error } }
    }

    /// Starts prefetching again each time the connection turns cheap, as when Wi-Fi comes back, until the calling
    /// task is cancelled. Sync starts prefetch too, but a sync may be a while off.
    func prefetchWhenConnectionAllows() async {
        for await _ in path.becameAllowed() {
            // An account removed meanwhile has no prefetcher to start.
            for account in accounts { await (try? prefetcher(for: account.id))?.start() }
        }
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

    @concurrent private static func trim(_ database: MailDatabase, attachments: URL) async {
        do {
            try database.trimCache(attachments: attachments)
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "cache")
                .error("Couldn't trim the cache: \(error, privacy: .public)")
        }
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

    /// What the reader does on opening a thread: marks its cached bodies as read, which the cache cap evicts by,
    /// then fetches the latest.
    func open(_ thread: ThreadSummary.ID) async throws {
        try? await Self.store { [database] in try database.touchMessages(inThread: thread) }
        try await loadMessages(of: thread)
    }

    /// Fetches a thread's messages with their bodies into the store, where the thread view reads them.
    func loadMessages(of thread: ThreadSummary.ID) async throws {
        let fetchedAt = Date.now
        let messages = try await providers.provider(for: thread.accountID).messages(inThread: thread.threadID)
        try await Self.store { [database] in try database.save(messages, inThread: thread, fetchedAt: fetchedAt) }
    }

    /// A thread's messages, to answer its newest: the cached ones when they reach as far as the thread does,
    /// otherwise the provider's, fetched into the store first. Offline, the cached ones are the best there is.
    func messagesToAnswer(in thread: ThreadSummary.ID) async throws -> [Message] {
        let newest = try await Self.read { [database] in try database.thread(thread)?.date }
        let cached = try await Self.first(database.messages(inThread: thread))
        // The store keeps the thread's date to the millisecond and each message's whole, so allow a little.
        if let newest, let last = cached.last?.date, last.timeIntervalSince(newest) > -1 { return cached }
        do {
            try await loadMessages(of: thread)
        } catch {
            if cached.isEmpty { throw error }
            return cached
        }
        return try await Self.first(database.messages(inThread: thread))
    }

    /// The store's current value, without following it.
    private static func first(_ messages: AsyncThrowingStream<[Message], any Error>) async throws -> [Message] {
        for try await messages in messages { return messages }
        return []
    }

    /// Runs a database read off the main actor, for the same reason as `store`.
    @concurrent private static func read<Value: Sendable>(_ read: @Sendable () throws -> Value) async throws -> Value {
        try read()
    }

    /// Runs a database write off the main actor. Any write can wait out another process's lock for seconds
    /// (ADR-002), and the larger ones take long enough by themselves to drop frames.
    @concurrent private static func store(_ write: @Sendable () throws -> Void) async throws {
        try write()
    }

    func attachmentData(_ attachment: Attachment, in message: Message.ID) async throws -> Data {
        try await providers.provider(for: message.accountID).data(for: attachment, in: message)
    }

    func source(of message: Message.ID) async throws -> Data {
        try await providers.provider(for: message.accountID).source(of: message)
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

    func engine(for id: AccountID) throws -> SyncEngine {
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

/// One sender per account, and the background session their sends go through. Each queued message is handed to
/// it once its undo window closes, with background time asked for so leaving the app in that window doesn't hold
/// it back; from then on the upload carries on even if the app is suspended or killed. One scheduled further ahead
/// is left to the next sync after its time: the foreground sync while the app is open, or a background refresh.
final class Senders {
    /// The longest wait held in background time; the longest undo window is 30 seconds.
    static let longestHeldWait: TimeInterval = 60

    var onSent: ((AccountID, [Draft]) async -> Void)?
    private let make: (AccountID, any UploadTransport) throws -> Sender
    private var senders: [AccountID: Sender] = [:]
    /// Made with the app model at launch, so iOS can hand over outcomes from earlier launches.
    private(set) lazy var uploads = BackgroundUploads { [weak self] ticket, outcome in
        // iOS may have woken the app in the background just for this.
        await BackgroundDatabaseWork.shared.run("Upload outcome") { await self?.complete(ticket, with: outcome) }
    }

    init(make: @escaping (AccountID, any UploadTransport) throws -> Sender) {
        self.make = make
        _ = uploads
    }

    func forget(_ id: AccountID) {
        senders[id] = nil
    }

    func deliver(_ id: AccountID, at date: Date) async {
        guard date.timeIntervalSinceNow <= Self.longestHeldWait else { return }
        await BackgroundDatabaseWork.shared.run("Send") {
            let wait = date.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let sender = sender(for: id) else { return }
            let went = await sender.flush()
            if !went.isEmpty { await onSent?(id, went) }
        }
    }

    private func complete(_ ticket: UploadTicket, with outcome: UploadOutcome) async {
        guard let sender = sender(for: ticket.accountID),
            let draft = await sender.complete(ticket.id, with: outcome)
        else { return }
        await onSent?(ticket.accountID, [draft])
    }

    private func sender(for id: AccountID) -> Sender? {
        if let sender = senders[id] { return sender }
        do {
            let sender = try make(id, uploads)
            senders[id] = sender
            return sender
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "send")
                .error("No sender: \(error, privacy: .public)")
            return nil
        }
    }
}
