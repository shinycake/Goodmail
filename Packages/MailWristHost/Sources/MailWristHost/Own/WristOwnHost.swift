public import Foundation
public import MailCore
public import MailStore
public import MailWrist
import Synchronization

#if canImport(FoundationNetworking)
    public import FoundationNetworking  // URLSession on Linux
#endif

/// The watch's own mail (ADR-023): a database of its own, one engine per Gmail or Outlook account it reads itself,
/// each keeping the newest `inboxLimit` Inbox conversations. It follows the iPhone's account list, syncs, and says
/// each account's source. Accounts it can't read stay with the iPhone, as ADR-022 describes.
public actor WristOwnHost {
    /// How many Inbox conversations the watch keeps for each account.
    public static let inboxLimit = 100

    public nonisolated let database: MailDatabase
    let signIns: WristSignIns
    private let provider: @Sendable (WristAccount) throws -> (any MailProvider)?
    let now: @Sendable () -> Date
    let commands: MailCommands
    let answers: ThreadAnswers
    /// Builds conversations from the watch's database, as the iPhone's host does from its own.
    private let conversations: WristMailHost
    let uploads: InlineUploads
    /// Where a send's upload body waits until its outcome is in.
    private let uploadFiles: URL
    /// The providers of `served`, for the reads that can't wait for the actor.
    private let shelf = ProviderShelf()
    /// The iPhone's accounts, in its order.
    var accounts: [WristAccount] = []
    /// The owner's switch, as the iPhone last said it.
    var independence = WristIndependence.default
    /// The accounts the watch reads itself: those whose provider could be made, which are those whose sign-in is here.
    var served: [AccountID: Served] = [:]
    /// How each account's syncs went.
    var health: [AccountID: AccountHealth] = [:]
    /// The catch-up in progress, which a second caller joins.
    private var catchingUp: Task<Void, Never>?
    /// Whether checks run now, and when one last worked. Only `run` changes it, through `start` and `end`.
    public private(set) var checking = Checking.idle(lastChecked: nil) {
        didSet { publishFreshness() }
    }
    /// The footer as it was last sent on `freshnessUpdates`.
    var published: WristFreshness?
    /// Each change to `freshness()`, for the list footer.
    public nonisolated let freshnessUpdates: AsyncStream<WristFreshness?>
    let freshnessContinuation: AsyncStream<WristFreshness?>.Continuation

    /// - Parameters:
    ///   - database: the watch app's own database, in its own container.
    ///   - provider: the account's client, or `nil` when its sign-in isn't here (`WristProviders.provider(for:)`).
    ///   - uploads: the folder where a Gmail send's body waits for its upload.
    ///   - http: what a Gmail send is uploaded through.
    public init(
        database: MailDatabase, signIns: WristSignIns,
        provider: @escaping @Sendable (WristAccount) throws -> (any MailProvider)?, uploads: URL,
        http: any HTTPClient = URLSession.shared, now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.database = database
        self.signIns = signIns
        self.provider = provider
        self.now = now
        uploadFiles = uploads
        self.uploads = InlineUploads(http: http)
        (freshnessUpdates, freshnessContinuation) = AsyncStream.makeStream(of: WristFreshness?.self)
        // The host drains the queues itself, after each command and before each sync, so none is left unowned.
        let commands = MailCommands(store: database, replay: { _ in }, now: now)
        self.commands = commands
        let answers = ThreadAnswers(database: database, commands: commands, provider: shelf.provider(for:))
        self.answers = answers
        conversations = WristMailHost(database: database, commands: commands, answers: answers)
    }

    /// A conversation of an account the watch reads itself, as the chat view shows it: from the database when it's
    /// current, otherwise fetched from the account's service first. `.gone` when the account or the conversation is.
    /// It works before the first sync since launch, as when an alert opens the app.
    public func conversation(_ id: ThreadSummary.ID) async throws -> WristThreadReply {
        serve()
        return try await conversations.conversation(id)
    }

    /// Each of the iPhone's accounts' source: direct once the watch has filled it, the iPhone otherwise.
    public func sources() throws -> [AccountID: WristAccountSource] {
        var syncStates: [AccountID: SyncState] = [:]
        for account in accounts { syncStates[account.id] = try database.syncState(for: account.id) }
        return WristAccountSources.resolve(
            accounts: accounts, signIns: try signIns.held(by: accounts), health: health, syncStates: syncStates,
            independence: independence)
    }

    /// The watch's own Inbox, again after every change to it, each made at `now()`.
    public nonisolated func snapshots() -> AsyncMapSequence<AsyncThrowingStream<InboxGlance, any Error>, WristSnapshot>
    {
        database.wristSnapshots(now: now)
    }

    /// Brings every account the watch reads itself up to date, as when the watch app comes to the front. Threads
    /// that left the Inbox since the last sync go first; the ones that leave it now stay until the next, so an undo
    /// still finds them. A failed sync is kept in the account's health; it throws only what the database threw.
    public func sync() async throws {
        guard independence == .on else { return }
        for id in served.keys { try database.pruneOutsideInbox(account: id) }
        serve()
        await drainQueues()
        await run { engine in try await engine.sync() }
    }

    /// Drops the threads that left the Inbox from every account the watch keeps, as at launch and when the app goes to
    /// the background, where no undo can still need them.
    public func prune() throws {
        for account in try database.accounts() { try database.pruneOutsideInbox(account: account.id) }
    }

    /// Fetches what changed since each filled account's cursor, as a background refresh does: no resync, no labels.
    /// A second caller while one runs joins it. Cancelling a caller, as the system does when a background refresh's
    /// time runs out, cancels the catch-up: what each account stored so far stays, and its health doesn't count it.
    public func catchUp() async {
        if let catchingUp { return await Self.wait(for: catchingUp) }
        let task = Task { await runCatchUp() }
        catchingUp = task
        defer { catchingUp = nil }
        await Self.wait(for: task)
    }

    private static func wait(for task: Task<Void, Never>) async {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func runCatchUp() async {
        guard independence == .on else { return }
        serve()
        await drainQueues()
        await run { engine in _ = try await engine.catchUp() }
    }

    /// Starts serving the accounts whose sign-in arrived since.
    func serve() {
        for account in accounts where served[account.id] == nil && WristSignIns.client(for: account) != nil {
            guard let provider = try? provider(account) else { continue }
            shelf.put(provider, for: account.id)
            served[account.id] = Served(
                engine: SyncEngine(
                    accountID: account.id, provider: provider, store: database,
                    scope: .inboxHead(limit: Self.inboxLimit), now: now),
                outbox: Outbox(accountID: account.id, provider: provider, store: database, now: now),
                sender: Sender(
                    accountID: account.id, provider: provider, store: database, transport: uploads,
                    uploads: uploadFiles, now: now))
        }
    }

    /// Stops serving an account, as when it leaves the watch.
    func stopServing(_ account: AccountID) {
        served[account] = nil
        shelf.put(nil, for: account)
    }

    /// Runs `step` on every served account's engine at once and keeps how each went.
    private func run(_ step: @escaping @Sendable (SyncEngine) async throws -> Void) async {
        let engines = served.mapValues(\.engine)
        checking.start()
        let outcomes = await withTaskGroup(of: (AccountID, Result<Void, any Error>).self) { group in
            for (id, engine) in engines {
                group.addTask {
                    do {
                        try await step(engine)
                        return (id, .success(()))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
        }
        // A run cut short says nothing about the accounts.
        guard !Task.isCancelled else {
            checking.end(workedAt: nil)
            return
        }
        let date = now()
        for (id, outcome) in outcomes where served[id] != nil {
            health[id] = (health[id] ?? .healthy).after(outcome, at: date)
        }
        let worked = outcomes.values.contains { if case .success = $0 { true } else { false } }
        checking.end(workedAt: worked ? date : nil)
    }
}

extension MailDatabase {
    /// The Inbox as the watch lists it, again after every change to it, each made at `now()` and carrying the
    /// `extras` of its accounts.
    func wristSnapshots(
        now: @escaping @Sendable () -> Date,
        extras: @escaping @Sendable ([Account]) -> WristExtras? = { _ in nil }
    ) -> AsyncMapSequence<AsyncThrowingStream<InboxGlance, any Error>, WristSnapshot> {
        inboxGlance(limit: WristSnapshot.rowLimit).map { glance in
            WristSnapshot(
                accounts: glance.accounts, threads: glance.threads, pinned: glance.pinned, unread: glance.unread,
                extras: extras(glance.accounts), madeAt: now())
        }
    }
}

/// What the watch keeps for an account it reads itself.
struct Served {
    let engine: SyncEngine
    let outbox: Outbox
    let sender: Sender
}

/// The providers of the served accounts, readable from anywhere, as `ThreadAnswers` needs.
private final class ProviderShelf: Sendable {
    private let providers = Mutex<[AccountID: any MailProvider]>([:])

    func put(_ provider: (any MailProvider)?, for account: AccountID) {
        providers.withLock { $0[account] = provider }
    }

    func provider(for account: AccountID) throws -> any MailProvider {
        guard let provider = providers.withLock({ $0[account] }) else { throw ProviderError.notFound }
        return provider
    }
}

extension MailDatabase {
    /// A stream's current value, without following it.
    func firstValue<Element>(of stream: AsyncThrowingStream<[Element], any Error>) async throws -> [Element] {
        for try await value in stream { return value }
        return []
    }
}
