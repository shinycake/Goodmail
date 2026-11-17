public import Foundation
public import MailCore
public import MailStore
public import MailWrist

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
    /// The iPhone's accounts, in its order.
    var accounts: [WristAccount] = []
    /// The owner's switch, as the iPhone last said it.
    var independence = WristIndependence.default
    /// The engines of the accounts whose provider could be made, which are those whose sign-in is here.
    var engines: [AccountID: SyncEngine] = [:]
    /// How each account's syncs went.
    var health: [AccountID: AccountHealth] = [:]
    /// The catch-up in progress, which a second caller joins.
    private var catchingUp: Task<Void, Never>?

    /// - Parameters:
    ///   - database: the watch app's own database, in its own container.
    ///   - provider: the account's client, or `nil` when its sign-in isn't here (`WristProviders.provider(for:)`).
    public init(
        database: MailDatabase, signIns: WristSignIns,
        provider: @escaping @Sendable (WristAccount) throws -> (any MailProvider)?,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.database = database
        self.signIns = signIns
        self.provider = provider
        self.now = now
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
        for id in engines.keys { try database.pruneOutsideInbox(account: id) }
        await run(on: readable()) { engine in try await engine.sync() }
    }

    /// Fetches what changed since each filled account's cursor, as a background refresh does: no resync, no labels.
    /// A second caller while one runs joins it.
    public func catchUp() async {
        if let catchingUp { return await catchingUp.value }
        let task = Task { await runCatchUp() }
        catchingUp = task
        defer { catchingUp = nil }
        await task.value
    }

    private func runCatchUp() async {
        guard independence == .on else { return }
        await run(on: readable()) { engine in _ = try await engine.catchUp() }
    }

    /// The engines of the accounts the watch can read, made for any whose sign-in arrived since.
    private func readable() -> [AccountID: SyncEngine] {
        for account in accounts where engines[account.id] == nil && WristSignIns.client(for: account) != nil {
            guard let provider = try? provider(account) else { continue }
            engines[account.id] = SyncEngine(
                accountID: account.id, provider: provider, store: database,
                scope: .inboxHead(limit: Self.inboxLimit), now: now)
        }
        return engines
    }

    /// Runs `step` on every engine at once and keeps how each went.
    private func run(
        on engines: [AccountID: SyncEngine], _ step: @escaping @Sendable (SyncEngine) async throws -> Void
    ) async {
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
        let date = now()
        for (id, outcome) in outcomes where self.engines[id] != nil {
            health[id] = (health[id] ?? .healthy).after(outcome, at: date)
        }
    }
}

extension MailDatabase {
    /// The Inbox as the watch lists it, again after every change to it, each made at `now()`.
    func wristSnapshots(
        now: @escaping @Sendable () -> Date
    ) -> AsyncMapSequence<AsyncThrowingStream<InboxGlance, any Error>, WristSnapshot> {
        inboxGlance(limit: WristSnapshot.rowLimit).map { glance in
            WristSnapshot(
                accounts: glance.accounts, threads: glance.threads, pinned: glance.pinned, unread: glance.unread,
                madeAt: now())
        }
    }
}
