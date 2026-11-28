import MailCore
import OSLog
import UIKit

/// Decides when sync runs, by presence (ADR-033): at once when the reader comes to the app, then every 30 seconds
/// while they are with it, every 5 minutes on a Mac while no one looks, as soon as a watched server reports a change
/// (ChangeWatchers, IMAP IDLE), and on iOS in background app refresh (BackgroundRefresh), which is asked for on
/// leaving the foreground. On a Mac, waking from sleep and the network coming back open the watches afresh and sync
/// at once.
/// Push wakes the notification extension when the app isn't open; while it is, the watches and this polling show
/// new mail.
final class SyncScheduler {
    private let model: AppModel
    /// Background app refresh, which `AppLaunch` hands the tasks iOS starts.
    let refresh: BackgroundRefresh
    private let presence: PresenceTracker
    private let watchers: ChangeWatchers
    private let log = Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
    /// The rounds of sync, while presence gives them an interval.
    private var rounds: Task<Void, Never>?
    /// Mac: starts the watches and the rounds afresh each time the network comes back, for the life of the process.
    private var networkReturns: Task<Void, Never>?
    /// Stops prefetching, then asks for the next background refresh, on leaving the foreground. The ask reads the
    /// database as iOS may suspend the app, so it runs inside `BackgroundDatabaseWork`, which keeps the app awake and
    /// the database usable until it ends, and suspends the database under it if that time runs out (0xdead10cc). Each
    /// leave's ask waits for the one before, so they never overlap and the last one asked is the one that stands.
    private var scheduling: Task<Void, Never>?

    init(model: AppModel, presence: PresenceTracker) {
        self.model = model
        self.presence = presence
        refresh = BackgroundRefresh(model: model, database: model.database)
        watchers = ChangeWatchers(model: model, policy: presence.policy)
    }

    /// Call once, when the database has opened. That can be after the reader came to the app, so the rounds start
    /// at once then.
    func start() {
        // Each sync of every account made their sessions: the watches follow at once, without waiting for it to end.
        model.didMakeSessions = { [weak watchers] in watchers?.follow() }
        #if DEBUG
            TestRefresh.runIfRequested(refresh)
        #endif
        presence.follow { [weak self] _, new in
            switch new {
            // The reader came to the app: sync at once.
            case .attended: self?.startRounds()
            case .suspendable: self?.leave()
            // The rounds go on as they were, at the new presence's interval.
            case .covered, .arriving, .unattended: break
            }
        }
        if presence.presence.syncInterval != nil { startRounds() }
        switch presence.policy {
        case .suspends: break
        case .keepsRunning:
            networkReturns = Task { [weak self, model] in
                for await _ in model.path.allowsMore() { self?.resume() }
            }
        }
    }

    /// iOS may suspend the app from now on: what runs stops, and background app refresh takes over.
    private func leave() {
        rounds?.cancel()
        watchers.stop()
        model.shareSettingsNow()
        let previous = scheduling
        scheduling = Task { [model, refresh] in
            await model.cancelPrefetch()
            await previous?.value
            await BackgroundDatabaseWork.shared.run("Schedule refresh") { await refresh.schedule() }
        }
    }

    /// Mac: the connections from before may be dead without knowing it yet.
    private func resume() {
        watchers.restart()
        startRounds()
    }

    private func startRounds() {
        rounds?.cancel()
        watchers.start()
        rounds = Task { [model, log, watchers, presence] in
            // Leaving the foreground cancels this, and the sync under way may be writing: the app stays awake, and the
            // database usable, until it stops.
            await BackgroundDatabaseWork.shared.run("Sync") {
                await withDiscardingTaskGroup { group in
                    group.addTask { await model.prefetchWhenConnectionAllows() }
                    while !Task.isCancelled {
                        // Whether the reader is with the app as the round begins, so what it brings counts as seen.
                        let shown = presence.presence.showsMail
                        // Accounts the reader's other devices added, removed or offer since the last round.
                        do {
                            try await model.followSharedAccounts()
                        } catch {
                            log.error("Following the shared accounts failed: \(error, privacy: .private)")
                        }
                        // Settings changed here or on the other devices, for the accounts here now.
                        await model.syncSettings()
                        do {
                            try await model.syncAll()
                            if shown { await model.markInboxSeen() }
                        } catch {
                            log.error("Sync failed: \(error, privacy: .private)")
                        }
                        guard let interval = presence.presence.syncInterval else { break }
                        let began = ContinuousClock.now
                        try? await Task.sleep(for: interval)
                        if case .keepsRunning = presence.policy,
                            Oversleep.meansTheDeviceSlept(asked: interval, took: ContinuousClock.now - began)
                        {
                            // The Mac slept: the next round syncs at once, and the watches start afresh.
                            watchers.restart()
                        }
                    }
                    group.cancelAll()
                }
            }
        }
    }
}
