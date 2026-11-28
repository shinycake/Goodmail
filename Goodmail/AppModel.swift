import Foundation
import GmailProvider
import IMAPProvider
import MailCore
import MailStore
import MailUI
import MailWristHost
import OSLog
import OutlookProvider
import UIKit

/// The composition root, shared by every window: the database, the accounts, each account's sync engine, and the
/// commands that change mail.
final class AppModel {
    /// The sync Get Mail started, while it runs. Only `getMail()` sets it.
    private var gettingMail: Task<Void, Never>?
    /// Every read and write awaits, off the main actor (ADR-043).
    let database: OffMainDatabase
    let commands: MailCommands
    /// Reads and answers conversations, for alert replies, the watch and the composer's quote.
    let answers: ThreadAnswers
    /// The stored accounts and their signatures as the database last said, followed from every writer: this app, a
    /// sync, another process. Every screen and the sessions (`Providers`) read it at once (ADR-043).
    let stored: FollowedValue<StoredAccounts>
    /// The stored accounts, in the reader's order.
    var accounts: [Account] { stored.latest.accounts }
    /// Each account's stored signature, where it has one, for the composer to start a message with.
    var signatures: [AccountID: String] { stored.latest.signatures }
    /// Each account's session: its provider, sync engine and prefetcher.
    let providers: Providers
    /// How much the connection allows. Prefetch follows it, and so does sync on a Mac, to start afresh when it comes
    /// back.
    let path: PathMonitor
    /// Fetches threads as they open, joining a fetch their row began when touched or scrolled into view.
    let threadFetcher: ThreadFetcher
    /// The work started from synchronous code: the outbox replays and sends the commands ask for as they change mail,
    /// and handing the lists' read-ahead to `threadFetcher`. The model's own, cancelled with it.
    private let errands = Errands()
    /// The read-ahead requests the lists make (`readAhead(_:)`), handed to `threadFetcher` in the order they came.
    let readAheads: AsyncStream<ThreadFetcher.Request>.Continuation
    /// Where opened attachments are kept; they count toward the cache cap with the bodies.
    let attachmentsDirectory = URL.cachesDirectory.appending(path: "Attachments", directoryHint: .isDirectory)
    let outboxes: Outboxes
    /// What this kind of device keeps offline and may spend on downloaded mail (ADR-007), decided once here: a Mac
    /// has room a phone doesn't.
    let storage = StoragePreferences(window: ProcessInfo.processInfo.isMacCatalystApp ? .desktop : .handheld)
    /// How each account's syncs are going, for the mailbox lists to tell the reader of a problem.
    let health = AccountHealthBoard()
    /// Senders' photos and logos for the mail screens.
    let senderPictures: SenderPictures
    /// The messages minimized in each window, kept for the next launch.
    let minimizedDrafts: MinimizedDrafts
    /// Apply Rules, Block Sender and VIPs, for every window (ADR-038).
    private(set) lazy var senderRules = SenderRules(service: senderRulesService())
    /// How Settings reads and stores the rules: one for the app, so every Settings window's reads and saves run in
    /// one order (`MailRules.Service.order`).
    private(set) lazy var rulesService = makeRulesService()
    /// The alerts shown once a launch in the front viewer, whichever windows open.
    private(set) lazy var launchAlerts = LaunchAlerts(database: database) { [weak self] in
        await self?.gmailAccountsToSignInAgain() ?? []
    }
    private let senders: Senders
    /// Keeps each account's push subscription current; `nil` when the build names no push relay.
    let pushRegistrar: PushRegistrar?
    /// This device's APNs token, once iOS hands it over.
    var pushDevice: DeviceToken?
    /// The Apple Watch choice for Settings, while a paired watch has the app (`WristHost`).
    var watchChoices: WatchChoices?
    /// Runs after an account is added, so alerts can be asked for and set up.
    var didAddAccount: (() -> Void)?
    /// Runs as each sync of every account begins, once it made their sessions, so the watches follow the accounts
    /// added, removed or signed in afresh without waiting for the sync to end.
    var didMakeSessions: (() -> Void)?
    /// Told after the stored mail changes in bulk, so the system's copies (Spotlight) can follow.
    var didChange: (@Sendable (MailChange) async -> Void)?
    /// Where accounts are shared with the reader's other devices; `nil` keeps every account on this device alone, as
    /// in synthetic mailboxes.
    let sharing: AccountSharing?
    /// What the last pass with the other devices found to offer (`followSharedAccounts`), read against `accounts`
    /// as `sharedElsewhere` and `restorable`.
    var sharingFindings = SharingFindings()
    /// The pass bringing this device in step with the others, while one runs (`followSharedAccounts`).
    var sharingPass: Task<Void, any Error>?
    /// Keeps the reader's settings the same on their other devices; `nil` keeps them on this device, as in synthetic
    /// mailboxes.
    let settingsSync: SettingsSync?
    /// The pass sharing what the reader just changed, while one runs (`shareSettingsNow`).
    var settingsShare: Task<Void, Never>?
    /// Keeps pins, snoozes and device mutes the same on the reader's other devices (ADR-037); `nil` keeps them here.
    let mailStateSync: SettingsSync?

    nonisolated enum MailChange: Sendable {
        /// A sync finished, of every account or of one whose server reported a change.
        case synced
        /// An account and its mail left the device.
        case accountRemoved
    }

    /// `pushRelay` is where accounts subscribe to push; `nil` keeps alerts off, as in synthetic mailboxes. `sharing`
    /// is where accounts are shared with the reader's other devices, and `settingsSync` and `mailStateSync` keep
    /// settings and mail state in step with them. `stored` is what the database holds of the accounts, read off the
    /// main actor as it opened; the model follows it from there.
    init(
        database: OffMainDatabase, stored: StoredAccounts, pushRelay: URL? = PushConfiguration.relayURL,
        sharing: AccountSharing? = nil, settingsSync: SettingsSync? = nil, mailStateSync: SettingsSync? = nil
    ) {
        self.database = database
        self.sharing = sharing
        self.settingsSync = settingsSync
        self.mailStateSync = mailStateSync
        // The actors below read and write the blocking database on their own executors.
        senderPictures = .cached(with: database.blocking)
        minimizedDrafts = MinimizedDrafts(database: database.blocking)
        let followed = FollowedValue(
            stored, following: { database.accountsAndSignatures() },
            reading: { try await database.offMain { try $0.storedAccounts() } },
            log: MailLog(category: "accounts"))
        self.stored = followed
        pushRegistrar = pushRelay.map {
            let attestation = RelayAttestation(baseURL: $0, device: AppAttestDevice(), store: Keychain())
            return PushRegistrar(relay: PushRelayClient(baseURL: $0, signer: attestation), store: database.blocking)
        }
        let path = PathMonitor()
        self.path = path
        let (storage, attachments) = (storage, attachmentsDirectory)
        let cache = database.blocking  // blocking-reads: allow: read only by `hasRoom`, on the prefetcher's actor
        let providers = Providers(accounts: followed, index: database.blocking) { id, provider in
            AccountSession(
                provider: provider,
                engine: SyncEngine(
                    accountID: id, provider: provider, store: database.blocking, scope: .window(storage.window)),
                prefetcher: BodyPrefetcher(
                    accountID: id, provider: provider, store: database.blocking, path: path,
                    scope: { storage.prefetchScope },
                    hasRoom: { cache.hasRoomToPrefetch(under: storage.cacheLimit) },
                    didFinish: { await Self.trim(database, attachments: attachments, limit: storage.cacheLimit) }))
        }
        self.providers = providers
        let threadFetcher = ThreadFetcher(
            provider: { try providers.provider(for: $0) }, store: database.blocking, path: path,
            scope: { [storage] in storage.prefetchScope })
        self.threadFetcher = threadFetcher
        // One errand hands them over, one after another: a skip that came after a read-ahead of the same rows must
        // land after it.
        let (readAheadRequests, readAheads) = AsyncStream.makeStream(of: ThreadFetcher.Request.self)
        self.readAheads = readAheads
        let errands = errands
        errands.start {
            for await request in readAheadRequests { await threadFetcher.handle(request) }
        }
        let outboxes = Outboxes { id in
            Outbox(accountID: id, provider: { try providers.provider(for: id) }, store: database.blocking)
        }
        self.outboxes = outboxes
        let uploads = URL.applicationSupportDirectory.appending(path: "Uploads", directoryHint: .isDirectory)
        let senders = Senders { id, transport in
            Sender(
                accountID: id, provider: { try providers.provider(for: id) }, store: database.blocking,
                transport: transport,
                uploads: uploads)
        }
        self.senders = senders
        commands = MailCommands(
            store: database.blocking,
            replay: { id in errands.start { await outboxes.flush(id) } },
            deliver: { id, date in errands.start { await senders.deliver(id, at: date) } })
        answers = ThreadAnswers(database: database.blocking, commands: commands, provider: providers.provider(for:))
        // A sent message lands in its thread on the server; fetch it so the list and the reader show it there.
        senders.onSent = { [weak self] id, sent in await self?.followSent(sent, from: id) }
    }

    /// Syncs the account messages were just sent from, telling `health` how it went as every sync does, then fetches
    /// the threads they landed in. A thread that doesn't load shows them on the next sync.
    private func followSent(_ sent: [Draft], from id: AccountID) async {
        let engine = Result { try engine(for: id) }
        let outcome = await Result { try await engine.get().sync() }
        if speaksForTheAccount(engine, id) { health.record(outcome, for: id) }
        for threadID in Set(sent.compactMap(\.threadID)) {
            do {
                try await loadMessages(of: ThreadSummary.ID(accountID: id, threadID: threadID))
            } catch {
                Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
                    .error("Couldn't load the thread of a sent message: \(error, privacy: .private)")
            }
        }
    }

    /// iOS launched or woke the app to hand over the outcomes of uploads that finished while it was away.
    func handleBackgroundUploadEvents(_ completion: @escaping @MainActor () -> Void) {
        senders.uploads.handleEvents(completion: completion)
    }

    /// The shared container's database, so the extensions see the same mail (ADR-002).
    static func openShared() async throws -> AppModel {
        // Unsigned simulator builds have no App Group.
        let directory = SharedContainer.directoryURL ?? URL.applicationSupportDirectory
        let database = try await OffMainDatabase.open(url: directory.appending(path: "Mail/mail.sqlite"))
        return AppModel(
            database: database, stored: try await database.offMain { try $0.storedAccounts() },
            sharing: AccountSharing(shared: Keychain.iCloud, device: Keychain(), signInKey: Providers.signInKey),
            settingsSync: .synced(database), mailStateSync: .mailState(database))
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
            OutlookClient(session: $0, index: database.blocking)
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
        // An address the reader's other devices have keeps their ID, so it stays one account across devices.
        let existing = (accounts + sharedElsewhere).filter { $0.service == service }
        let (session, email) = try await OAuthSession.signIn(
            client: client, code: code, pkce: pkce,
            accountID: { email in
                existing.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }?.id ?? .generate()
            },
            keychain: Keychain.signIns(),
            endingTheOld: { [providers] id in await providers.reload(id) })
        await providers.use(provider(session), for: session.accountID)
        if !accounts.contains(where: { $0.id == session.accountID }) {
            let account = Account(
                id: session.accountID,
                email: email,
                color: AccountColor.next(after: accounts.map(\.color)),
                service: service
            )
            try await store(account)
            didAddAccount?()
        }
        await didSignIn(session.accountID)
        await syncAfterAdding()
        return true
    }

    /// Checks the app-specific password by logging in to iCloud, then adds the account, or updates the password of
    /// the one already here. Throws `ICloudSignIn.Failure.wrongPassword` when iCloud refuses it.
    func addICloudAccount(email: String, appPassword: String) async throws {
        try await addPasswordAccount(.icloud, email: email) { email, id in
            try await ICloudSignIn(secrets: Keychain.signIns()).signIn(
                email: email, appPassword: appPassword, accountID: id)
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
        let id = existing?.id ?? sharedID(of: service, email) ?? .generate()
        try await signIn(email, id)
        await providers.reload(id)
        if existing == nil {
            let account = Account(
                id: id, email: email,
                color: AccountColor.next(after: accounts.map(\.color)), service: service, name: name)
            try await store(account)
        }
        await didSignIn(id)
        await syncAfterAdding()
    }

    /// Adds accounts from the other devices, whose sign-ins came with them. The next sync fills them in.
    func adopt(_ shared: [Account]) async throws {
        let new = shared.filter { account in !accounts.contains { $0.id == account.id } }
        guard !new.isEmpty else { return }
        for account in new {
            // One removed earlier in this launch gets a session again.
            await providers.reload(account.id)
            try await store(account)
        }
        didAddAccount?()
    }

    /// Syncs every account once one was added. The account is already here, so a failed sync doesn't undo it or say
    /// the sign-in failed, least of all when it's another account that can't sync. The next sync tries again.
    func syncAfterAdding() async {
        do {
            try await syncAll()
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
                .error("The sync after adding an account failed: \(error, privacy: .private)")
        }
    }

    /// Signs the account out and takes it and its mail off this device, or off every device that shares accounts.
    /// Nothing changes at its service.
    func removeAccount(_ id: AccountID, _ removal: AccountRemoval) async throws {
        // Told to the other devices before anything goes: if that fails, the account stays everywhere, rather than a
        // device that follows the others taking back what the reader removed here.
        if removal == .everyDevice { try await activeSharing?.retire(id) }
        // While the account can still prove its address to the relay.
        await unsubscribePush(id)
        // Before its sign-in goes, so a token refresh under way can't write it back.
        await providers.remove(id)
        if let account = accounts.first(where: { $0.id == id }) { await signOut(account, removal) }
        // Takes every thread and body of the account with it, which can be most of the database.
        try await changeAccounts { try $0.removeAccount(id) }
        try? FileManager.default.removeItem(at: attachmentsDirectory.appending(path: id.rawValue))
        // Its sign-in is gone, so a reinstall's offer can't bring it back.
        sharingFindings.removed(id)
        health.forget(id)
        await didChange?(.accountRemoved)
    }

    /// Stores the account's new name or color, and shares it with the reader's other devices.
    func update(_ account: Account) async throws {
        try await keep(account)
        await shareAccounts()
    }

    /// Stores the order the reader put the accounts in, which every list of accounts follows, and shares it.
    func reorderAccounts(_ order: [AccountID]) async throws {
        try await keep(order: order)
        await shareAccounts()
    }

    /// Stores the account's name and color on this device alone, as when another device changed them.
    func keep(_ account: Account) async throws {
        try await changeAccounts { try $0.update(account) }
    }

    /// Stores the accounts' order on this device alone, as when another device changed it.
    func keep(order: [AccountID]) async throws {
        try await changeAccounts { try $0.reorderAccounts(order) }
    }

    /// Get Mail from any window: syncs every account in one task the app owns, which a second Get Mail joins and
    /// which outlives the window that asked. A failure shows on the health board.
    func getMail() {
        guard gettingMail == nil else { return }
        gettingMail = Task { [weak self] in
            try? await self?.syncAll()
            self?.gettingMail = nil
        }
    }

    /// Sends queued actions, then syncs, every account at once, and tells `health` how each went. Each engine
    /// coalesces overlapping calls, so this is safe to call often. One account that fails doesn't stop the others;
    /// once all are done, the first account's failure is thrown, which `health` already has unless it no longer
    /// speaks for that account. One before the accounts', as waking the snoozed threads, is logged and stops nothing.
    /// With `prefetch`, each account that synced then starts fetching bodies in the background (ADR-007); a background
    /// refresh leaves that to the next time the app is open.
    func syncAll(prefetch: Bool = true) async throws {
        health.syncStarted()
        defer { health.syncEnded() }
        // An account whose login is gone from the Keychain has no provider, which is its failure to sync.
        let engines = accounts.map { account in (account.id, Result { try engine(for: account.id) }) }
        didMakeSessions?()
        let outboxes = outboxes
        // Snoozed threads whose time came, queued before the replay below so the server hears of them now. What the
        // other devices pinned, snoozed, woke or muted is taken up first, so a thread one of them woke isn't woken
        // twice, and a wake made here is shared at once so the others don't wake it too.
        await syncMailState()
        do {
            if try await !commands.wakeSnoozed().isEmpty { await syncMailState() }
        } catch {
            // No account's sync tells of it, so it's logged here. They go on, and the next sync wakes the threads.
            Logger.snooze.error("Couldn't wake the snoozed threads that are due: \(error, privacy: .private)")
        }
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
        for (id, engine) in engines where speaksForTheAccount(engine, id) {
            if let outcome = outcomes[id] { health.record(outcome, for: id) }
        }
        let synced = accounts.filter { if case .success = outcomes[$0.id] { true } else { false } }
        // With nothing new stored, the accounts, the cache and the system's copies (Spotlight) have nothing to follow.
        if !synced.isEmpty {
            await runRules(for: synced)
            if prefetch { for account in synced { await (try? prefetcher(for: account.id))?.start() } }
            await trimCache()
            await didChange?(.synced)
        }
        for account in accounts { if case .failure(let error) = outcomes[account.id] { throw error } }
    }

    /// Starts prefetching again each time the connection allows more, as when Wi-Fi comes back, until the calling
    /// task is cancelled. Sync starts prefetch too, but a sync may be a while off.
    func prefetchWhenConnectionAllows() async {
        for await _ in path.allowsMore() {
            // An account removed meanwhile has no prefetcher to start.
            for account in accounts { await (try? prefetcher(for: account.id))?.start() }
        }
    }

    /// Fetches the bodies of a few of each account's newest threads, as a background refresh does after its sync, so
    /// the mail that came meanwhile opens at once. Waits for them, unlike `start()`, since the refresh's time is short.
    func prefetchNewest() async {
        let prefetchers = accounts.compactMap { try? prefetcher(for: $0.id) }
        await withTaskGroup(of: Void.self) { group in
            for prefetcher in prefetchers {
                group.addTask { await prefetcher.run(atMost: Self.backgroundPrefetchCount) }
            }
        }
        await trimCache()
    }

    /// How many threads per account a background refresh fetches the bodies of: what a few seconds allow.
    private static let backgroundPrefetchCount = 20

    /// Stops prefetching, as when the app leaves the foreground. The next sync picks up where it left off.
    func cancelPrefetch() async {
        for session in providers.live.values { await session.prefetcher.cancel() }
        await threadFetcher.cancelReadAhead()
    }

    /// Evicts the least recently read bodies and attachments when the cache is over its cap (ADR-007). Off the
    /// main thread: it scans the attachments folder.
    private func trimCache() async {
        await Self.trim(database, attachments: attachmentsDirectory, limit: storage.cacheLimit)
    }

    private nonisolated static func trim(_ database: OffMainDatabase, attachments: URL, limit: Int) async {
        do {
            try await database.offMain { _ = try $0.trimCache(to: limit, attachments: attachments) }
        } catch {
            Logger(subsystem: "com.idanbirman.goodmail", category: "cache")
                .error("Couldn't trim the cache: \(error, privacy: .private)")
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
        do {
            try await database.offMain { try $0.touchMessages(inThread: thread) }
        } catch {
            // The thread still opens; its bodies only stay as old to the cache cap as they were.
            Logger(subsystem: "com.idanbirman.goodmail", category: "cache")
                .error("Couldn't mark an opened thread's bodies as read: \(error, privacy: .private)")
        }
        try await loadMessages(of: thread)
    }

    /// Fetches a thread's messages with their bodies into the store, where the thread view reads them.
    func loadMessages(of thread: ThreadSummary.ID) async throws {
        try await threadFetcher.load(thread)
    }

    /// A thread's messages, to answer its newest (`ThreadAnswers.messagesToAnswer(in:)`).
    func messagesToAnswer(in thread: ThreadSummary.ID) async throws -> [Message] {
        try await answers.messagesToAnswer(in: thread)
    }

    /// Stores the new account, and returns once `accounts` has it, so its session can be made.
    private func store(_ account: Account) async throws {
        try await changeAccounts { try $0.save(account) }
    }

    /// Writes `change` off the main actor, then waits until the followed accounts are as new as the revision it
    /// returns, so what the caller does next, as making a session or sharing the accounts, sees it, whatever else
    /// changed them meanwhile (ADR-043). Throws only when the write fails: if the accounts can't be read to show it,
    /// the change still stands, and the next read shows it.
    private func changeAccounts(_ change: @escaping @Sendable (MailDatabase) throws -> Int) async throws {
        let revision = try await database.offMain { try change($0) }
        await show(revision)
    }

    /// Waits until the followed accounts are as new as `revision`.
    func show(_ revision: Int) async {
        guard await stored.wait(forRevision: revision) else {
            return Logger(subsystem: "com.idanbirman.goodmail", category: "accounts")
                .error("A change to the accounts was stored, but the model didn't see it")
        }
    }

    /// A part's data, from its kept file, or fetched and kept, so a body's inline images download once. Off the main
    /// actor, as every provider call is: IMAP and Outlook read the message index as they fetch (ADR-043).
    @concurrent nonisolated func attachmentData(_ attachment: Attachment, in message: Message.ID) async throws -> Data {
        let files = AttachmentFiles(root: attachmentsDirectory)
        if let data = await files.cachedData(for: attachment, in: message) { return data }
        let data = try await providers.provider(for: message.accountID).data(for: attachment, in: message)
        // A file that can't be kept, as on a full disk, costs only the next fetch.
        _ = try? await files.keep(data, for: attachment, in: message)
        return data
    }

    @concurrent nonisolated func source(of message: Message.ID) async throws -> Data {
        try await providers.provider(for: message.accountID).source(of: message)
    }

    /// Whether a sync on `engine` still tells of the account: not once it was removed, or signed in afresh, as with
    /// a new password, while the sync ran on the old sign-in. One whose engine couldn't be made tells of an account
    /// still here.
    func speaksForTheAccount(_ engine: Result<SyncEngine, any Error>, _ id: AccountID) -> Bool {
        switch engine {
        case .success(let engine): providers.live[id]?.engine === engine
        case .failure: accounts.contains { $0.id == id }
        }
    }

    private func prefetcher(for id: AccountID) throws -> BodyPrefetcher {
        try providers.session(for: id).prefetcher
    }

    func engine(for id: AccountID) throws -> SyncEngine {
        try providers.session(for: id).engine
    }
}

/// One sender per account for the launch, and the background session their sends go through. Each queued message is
/// handed to it once its undo window closes, with background time asked for so leaving the app in that window
/// doesn't hold it back; from then on the upload carries on even if the app is suspended or killed. One scheduled
/// further ahead is left to the next sync after its time: the foreground sync while the app is open, or a background
/// refresh. A sender reads the account's provider as each send begins, so it follows a new sign-in, and its drains
/// never overlap one another's.
final class Senders {
    /// The longest wait held in background time; the longest undo window is 30 seconds.
    static let longestHeldWait: TimeInterval = 60

    var onSent: ((AccountID, [Draft]) async -> Void)?
    private let make: (AccountID, any UploadTransport) -> Sender
    private var senders: [AccountID: Sender] = [:]
    /// Made with the app model at launch, so iOS can hand over outcomes from earlier launches.
    private(set) lazy var uploads = BackgroundUploads { [weak self] ticket, outcome in
        // iOS may have woken the app in the background just for this.
        await BackgroundDatabaseWork.shared.run("Upload outcome") { await self?.complete(ticket, with: outcome) }
    }

    init(make: @escaping (AccountID, any UploadTransport) -> Sender) {
        self.make = make
        _ = uploads
    }

    func deliver(_ id: AccountID, at date: Date) async {
        guard date.timeIntervalSinceNow <= Self.longestHeldWait else { return }
        await BackgroundDatabaseWork.shared.run("Send") {
            let sender = sender(for: id)
            // Logs in while the undo window runs, so only the message is left when it closes.
            await sender.prepare()
            let wait = date.timeIntervalSinceNow
            // A wait cut short sends nothing early: `flush` takes only the messages due by now.
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            let went = await sender.flush()
            if !went.isEmpty { await onSent?(id, went) }
        }
    }

    private func complete(_ ticket: UploadTicket, with outcome: UploadOutcome) async {
        guard let draft = await sender(for: ticket.accountID).complete(ticket.id, with: outcome) else { return }
        await onSent?(ticket.accountID, [draft])
    }

    private func sender(for id: AccountID) -> Sender {
        if let sender = senders[id] { return sender }
        let sender = make(id, uploads)
        senders[id] = sender
        return sender
    }
}
