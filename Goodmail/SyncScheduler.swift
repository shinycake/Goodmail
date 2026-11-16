import OSLog
import UIKit

/// Decides when sync runs: on becoming active, every 30 seconds while active, as soon as a watched server reports a
/// change (ChangeWatchers, IMAP IDLE), and in background app refresh (BackgroundRefresh), which is asked for on
/// leaving the foreground.
/// Push wakes the notification extension when the app isn't open; while it is, the watches and this polling show
/// new mail.
final class SyncScheduler {
    private static let foregroundInterval: Duration = .seconds(30)

    private let model: AppModel
    private let refresh: BackgroundRefresh
    private let watchers: ChangeWatchers
    private let log = Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
    private var foreground: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        refresh = BackgroundRefresh(model: model, database: model.database)
        watchers = ChangeWatchers(model: model)
    }

    /// Call once, before launch finishes: background task handlers must be registered by then.
    func start() {
        refresh.register()
        #if DEBUG
            TestRefresh.runIfRequested(refresh)
        #endif
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.startForegroundSync() }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.foreground?.cancel()
                self?.watchers.stop()
                if let model = self?.model { Task { await model.cancelPrefetch() } }
                self?.refresh.schedule()
            }
        }
    }

    private func startForegroundSync() {
        foreground?.cancel()
        watchers.start()
        foreground = Task { [model, log, watchers] in
            // Leaving the foreground cancels this, and the sync under way may be writing: the app stays awake, and the
            // database usable, until it stops.
            await BackgroundDatabaseWork.shared.run("Foreground sync") {
                async let prefetch: Void = model.prefetchWhenConnectionAllows()
                while !Task.isCancelled {
                    // Accounts added or removed meanwhile.
                    watchers.follow()
                    do {
                        try await model.syncAll()
                        await model.markInboxSeen()
                    } catch {
                        log.error("Foreground sync failed: \(error, privacy: .public)")
                    }
                    try? await Task.sleep(for: Self.foregroundInterval)
                }
                await prefetch
            }
        }
    }
}
