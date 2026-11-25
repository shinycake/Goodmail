import MailCore
import OSLog

/// While sync runs its rounds (`SyncScheduler`), keeps a watch on each account whose server reports changes as they
/// happen, as IMAP servers in IDLE do, and syncs the account each time one comes. The rounds go on beside it, for the
/// folders a watch doesn't see and the accounts no watch can serve.
final class ChangeWatchers {
    private enum State {
        case stopped
        /// Each watched account's watch. One that ended by itself, as on a server that can't IDLE or after a
        /// refused password, stays here. On iOS it isn't started again until the app next comes to the foreground or
        /// the account signs in afresh; on a Mac it tries again by itself after a wait (`WatchRestarts`), and at the
        /// next `restart()`.
        case watching([AccountID: Watch])
    }

    /// A watch, with the session whose provider it watches on.
    private struct Watch {
        let session: AccountSession
        let task: Task<Void, Never>
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

    /// Starts watching the accounts whose sessions were made since the last call, as by their first sync, stops
    /// watching the ones removed, and watches afresh the ones that signed in again meanwhile, as with a new password
    /// or server. Makes no session itself, which would read the database and the Keychain here on the main actor.
    func follow() {
        guard case .watching(var watches) = state else { return }
        let here = Set(model.accounts.map(\.id))
        let sessions = model.providers.live.filter { here.contains($0.key) }
        for (id, watch) in watches where sessions[id] !== watch.session {
            watch.task.cancel()
            watches[id] = nil
        }
        for (id, session) in sessions where watches[id] == nil {
            guard let provider = session.provider as? any ChangeWatching else { continue }
            watches[id] = Watch(session: session, task: watch(id, with: provider))
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
            for watch in watches.values { watch.task.cancel() }
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
