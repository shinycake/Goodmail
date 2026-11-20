import MailCore
import OSLog

/// While sync runs its rounds (`SyncScheduler`), keeps a watch on each account whose server reports changes as they
/// happen, as IMAP servers in IDLE do, and syncs the account each time one comes. The rounds go on beside it, for the
/// folders a watch doesn't see and the accounts no watch can serve.
final class ChangeWatchers {
    private enum State {
        case stopped
        /// Each watched account's watch. One that ended by itself, as on a server that can't IDLE or after a
        /// refused password, stays here. On iOS it isn't started again until the app next comes to the foreground; on
        /// a Mac it tries again by itself after a wait (`WatchRestarts`), and at the next `restart()`.
        case watching([AccountID: Task<Void, Never>])
    }

    private var state = State.stopped
    private let model: AppModel
    /// Whether a watch that ended starts again by itself.
    private let policy: PresencePolicy
    private let log = Logger(subsystem: "com.idanbirman.goodmail", category: "sync")

    init(model: AppModel, policy: PresencePolicy) {
        self.model = model
        self.policy = policy
    }

    /// Watches every account that can be watched, until `stop()`. Watches already running go on, as when the app
    /// becomes active again after Control Center covered it.
    func start() {
        if case .stopped = state { state = .watching([:]) }
        follow()
    }

    /// Starts watching the accounts added since the last call, and stops watching the ones removed.
    func follow() {
        guard case .watching(var watches) = state else { return }
        let ids = Set(model.accounts.map(\.id))
        for (id, watch) in watches where !ids.contains(id) {
            watch.cancel()
            watches[id] = nil
        }
        for id in ids where watches[id] == nil {
            guard let provider = try? model.providers.provider(for: id) as? any ChangeWatching else { continue }
            watches[id] = watch(id, with: provider)
        }
        state = .watching(watches)
    }

    /// Opens every watch afresh, as after the Mac slept or the network came back: a connection from before may be
    /// dead without knowing it yet, and each new one reports what changed meanwhile. Does nothing while stopped.
    func restart() {
        guard case .watching = state else { return }
        stop()
        start()
    }

    /// Cancels every watch, which closes its connection.
    func stop() {
        if case .watching(let watches) = state {
            for watch in watches.values { watch.cancel() }
        }
        state = .stopped
    }

    /// The watch runs off the main actor, and hops to it only to sync. Leaving the foreground cancels the watch, and
    /// the sync under way may be writing: the app stays awake, and the database usable, until it stops.
    private func watch(_ id: AccountID, with provider: any ChangeWatching) -> Task<Void, Never> {
        Task { @concurrent [model, log, policy] in
            var restarts = WatchRestarts(policy: policy)
            while true {
                let began = ContinuousClock.now
                do {
                    try await provider.watchChanges {
                        _ = await BackgroundDatabaseWork.shared.run("Reported change") { await model.syncChanged(id) }
                    }
                } catch is CancellationError {
                    // The app left the foreground, the account was removed, or the watches start afresh.
                    return
                } catch {
                    log.error("Watching an account for changes stopped: \(error, privacy: .public)")
                }
                guard let delay = restarts.delay(afterRunning: ContinuousClock.now - began) else { return }
                do { try await Task.sleep(for: delay) } catch { return }
            }
        }
    }
}
