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
    /// Where serving the watch's own mail records what it carried on without.
    static let log = MailLog(category: "own-mail")

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
    /// The providers of the served accounts, for `ThreadAnswers`, which reads them without waiting for the actor.
    /// Only `independence` sets it, after each change.
    private let shelf = ProviderShelf()
    /// The iPhone's accounts, in its order.
    var accounts: [WristAccount] = []
    /// The owner's switch, as the iPhone last said it, and the accounts the watch reads itself while it is on. Only
    /// `turn` moves the switch.
    var independence = Independence.off(ending: nil) {
        didSet {
            shelf.show(independence.served.mapValues(\.provider))
            publishFreshness()
        }
    }
    /// How each account's syncs went. Kept while the switch is off, so a sign-in turned down stays turned down.
    var health: [AccountID: AccountHealth] = [:] {
        didSet { publishFreshness() }
    }
    /// The catch-up in progress, which a second caller joins.
    private var catchingUp: Task<Void, Never>?
    /// The footer as it was last sent on `freshnessUpdates`.
    var published: WristFreshness?
    /// Each change to `freshness()`, for the list footer.
    public nonisolated let freshnessUpdates: AsyncStream<WristFreshness?>
    let freshnessContinuation: AsyncStream<WristFreshness?>.Continuation
    /// Takes what the watch gives back when the switch goes off: each change it couldn't make, for the iPhone to make
    /// instead, and each reply that didn't go.
    let handBack: Receiver

    /// - Parameters:
    ///   - database: the watch app's own database, in its own container.
    ///   - provider: the account's client, or `nil` when its sign-in isn't here (`WristProviders.provider(for:)`).
    ///   - uploads: the folder where a Gmail send's body waits for its upload.
    ///   - http: what a Gmail send is uploaded through.
    ///   - independence: the owner's switch as the watch last stored it, which the host starts in until the iPhone's
    ///     accounts are followed. Off, it gives back what the last launch left at once; on, it serves the copy as the
    ///     watch left it, once what a handover left undelivered has been delivered.
    ///   - handBack: takes what the watch gives back when the switch goes off, and keeps it before returning.
    public init(
        database: MailDatabase, signIns: WristSignIns,
        provider: @escaping @Sendable (WristAccount) throws -> (any MailProvider)?, uploads: URL,
        http: any HTTPClient = URLSession.shared, now: @escaping @Sendable () -> Date = { .now },
        independence: WristIndependence, handBack: @escaping Receiver
    ) async {
        self.database = database
        self.handBack = handBack
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
        switch independence {
        case .on: self.independence = .on(Stretch(readying: .asLeft, start: Task { try await ready(.asLeft) }))
        case .off: self.independence = .off(ending: Task { try? await settle() })
        }
    }

    /// A conversation of an account the watch reads itself, as the chat view shows it: from the database when it's
    /// current, otherwise fetched from the account's service first. `.gone` when the account or the conversation is.
    /// It works before the first sync since launch, as when an alert opens the app.
    public func conversation(_ id: ThreadSummary.ID) async throws -> WristThreadReply {
        guard try await serve() != nil else { throw Refusal.switchedOff }
        return try await conversations.conversation(id)
    }

    /// Each of the iPhone's accounts' source: direct once the watch has filled it, the iPhone otherwise.
    public func sources() async throws -> [AccountID: WristAccountSource] {
        // On again, the copy from before is forgotten first; until it is, every account is still filling.
        var syncStates: [AccountID: SyncState] = [:]
        if case .ready = await readiness() {
            for account in accounts { syncStates[account.id] = try database.syncState(for: account.id) }
        }
        return WristAccountSources.resolve(
            accounts: accounts, signIns: try signIns.held(by: accounts),
            health: health, syncStates: syncStates, independence: independence.position)
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
        let before = independence.served.keys
        guard let stretch = try await serve() else { return }
        for id in before { try database.pruneOutsideInbox(account: id) }
        await run(in: stretch) { engine in try await engine.sync() }
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
        guard let stretch = (try? await serve()) ?? nil else { return }
        await run(in: stretch) { engine in _ = try await engine.catchUp() }
    }

    /// Whether the stretch on now has readied the watch's copy.
    private enum Readiness {
        /// Ready, or the switch is off.
        case ready
        /// The start `start` of the stretch `stretch`, still its current one, failed.
        case failed(Task<Void, any Error>, in: Stretch.ID)
    }

    /// Waits for the stretch on now to have readied the watch's copy. A stretch the switch replaced meanwhile, or a
    /// start replaced by a retry, is waited for no more: the one after is.
    private func readiness() async -> Readiness {
        while let stretch = independence.stretch {
            let start = stretch.start
            let result = await start.result
            guard independence.stretch?.id == stretch.id, independence.stretch?.start == start else { continue }
            if case .failure = result { return .failed(start, in: stretch.id) }
            return .ready
        }
        return .ready
    }

    /// Readies the watch's copy for a stretch as `readying` says.
    func ready(_ readying: Stretch.Readying) async throws {
        switch readying {
        case .asLeft: try await redeliver()
        case .afresh: try await settle()
        }
    }

    /// Starts serving the accounts whose sign-in arrived since, once the stretch the switch is on in has readied
    /// the copy, which it tries again when it failed before. Returns the stretch, or `nil` while the switch is off,
    /// or when it went off meanwhile.
    func serve() async throws -> Stretch.ID? {
        guard let stretch = independence.stretch else { return nil }
        if case .failed(let start, let failed) = await readiness() {
            // Still current: `readiness` checked it after its wait, and nothing ran since.
            guard let current = independence.stretch, current.id == failed, current.start == start else {
                return try await serve()
            }
            independence.restart(failed, with: Task { try await ready(current.readying) })
            if case .failed = await readiness() { throw StartFailed() }
        }
        guard independence.stretch?.id == stretch.id else { return nil }
        for account in accounts where independence.served[account.id] == nil {
            guard let served = makeServed(account) else { continue }
            independence.serve(account.id, with: served, in: stretch.id)
        }
        return stretch.id
    }

    /// What the watch needs to read `account` itself; `nil` while its sign-in isn't here.
    func makeServed(_ account: WristAccount) -> Served? {
        guard WristSignIns.client(for: account) != nil, let provider = try? provider(account) else { return nil }
        return Served(
            provider: provider,
            engine: SyncEngine(
                accountID: account.id, provider: provider, store: database,
                scope: .inboxHead(limit: Self.inboxLimit), now: now),
            outbox: Outbox(accountID: account.id, provider: provider, store: database, now: now),
            sender: Sender(
                accountID: account.id, provider: provider, store: database, transport: uploads,
                uploads: uploadFiles, now: now))
    }

    /// The watch's copy couldn't be readied for the stretch, twice: the database failed, or what was given back
    /// couldn't be kept.
    struct StartFailed: Error {}

    /// Sends what every account served in `stretch` has queued, then runs `step` on its engine, all at once, and
    /// keeps how each went. The switch going off cancels it, as does cancelling the caller; either way it says
    /// nothing about the accounts. The switch going off waits for it, so no queue drains after the copy is forgotten
    /// and no later stretch drains it at the same time.
    private func run(in stretch: Stretch.ID, _ step: @escaping @Sendable (SyncEngine) async throws -> Void) async {
        guard independence.stretch?.id == stretch else { return }
        let check = Task { [served = independence.served, uploads] in
            await Self.outcomes(of: served, uploads: uploads, step)
        }
        let checkID = UUID()
        independence.track(check, as: checkID, in: stretch)
        let outcomes = await withTaskCancellationHandler {
            await check.value
        } onCancel: {
            check.cancel()
        }
        guard !check.isCancelled else {
            independence.finishCheck(checkID, in: stretch, workedAt: nil)
            return
        }
        let date = now()
        if let current = independence.stretch, current.id == stretch {
            for (id, outcome) in outcomes where independence.served[id] != nil {
                health[id] = (health[id] ?? .healthy).after(outcome, at: date)
            }
            // The queues were sent: a change with nothing left on its way is settled. One being made may not have
            // queued yet. Unread, or not removed, they wait for the next check.
            do {
                try database.removeSettledWatchChanges(except: Set(current.changes.values.map(\.command)))
            } catch {
                Self.log.error("Couldn't forget the watch's settled changes", error)
            }
        }
        let worked = outcomes.values.contains { if case .success = $0 { true } else { false } }
        independence.finishCheck(checkID, in: stretch, workedAt: worked ? date : nil)
    }

    @concurrent private static func outcomes(
        of served: [AccountID: Served], uploads: InlineUploads,
        _ step: @escaping @Sendable (SyncEngine) async throws -> Void
    ) async -> Outcomes {
        await withTaskGroup(of: (AccountID, Result<Void, any Error>).self) { group in
            for (id, served) in served {
                group.addTask {
                    // Before the sync reads them back. What doesn't go now goes on the next check.
                    do {
                        try await served.outbox.flush()
                    } catch {
                        Self.log.error("Couldn't send the watch's queued changes", error)
                    }
                    await deliver(served, account: id, uploads: uploads)
                    do {
                        try await step(served.engine)
                        return (id, .success(()))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
        }
    }

    /// Sends what `account` has due through `served`, and takes in how its uploads ended.
    static func deliver(_ served: Served, account: AccountID, uploads: InlineUploads) async {
        await served.sender.flush()
        for (id, outcome) in uploads.takeOutcomes(of: account) { _ = await served.sender.complete(id, with: outcome) }
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
    let provider: any MailProvider
    let engine: SyncEngine
    let outbox: Outbox
    let sender: Sender
}

/// The providers of the served accounts, readable from anywhere, as `ThreadAnswers` needs: it reads them
/// synchronously, off the actor, so it can't ask `independence` itself.
private final class ProviderShelf: Sendable {
    private let providers = Mutex<[AccountID: any MailProvider]>([:])

    /// Shows `providers` from now on, in place of the ones before.
    func show(_ providers: [AccountID: any MailProvider]) {
        self.providers.withLock { $0 = providers }
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
