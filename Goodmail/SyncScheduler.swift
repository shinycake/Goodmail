import BackgroundTasks
import OSLog
import UIKit

/// Decides when sync runs: on becoming active, every 30 seconds while active, and in background app refresh.
/// Push replaces the polling in M6; until then it is how new mail shows up while the app is open.
final class SyncScheduler {
    static let refreshTaskID = "com.idanbirman.goodmail.refresh"
    private static let foregroundInterval: Duration = .seconds(30)
    private static let backgroundInterval: TimeInterval = 15 * 60

    private let model: AppModel
    private let log = Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
    private var foreground: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    /// Call once, before launch finishes: background task handlers must be registered by then.
    func start() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { [weak self] task in
            guard let self, let task = task as? BGAppRefreshTask else { return }
            runBackgroundRefresh(task)
        }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.startForegroundSync() }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.foreground?.cancel()
                if let model = self?.model { Task { await model.cancelPrefetch() } }
                self?.scheduleBackgroundRefresh()
            }
        }
    }

    private func startForegroundSync() {
        foreground?.cancel()
        foreground = Task { [model, log] in
            while !Task.isCancelled {
                do {
                    try await model.syncAll()
                } catch {
                    log.error("Foreground sync failed: \(error, privacy: .public)")
                }
                try? await Task.sleep(for: Self.foregroundInterval)
            }
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.backgroundInterval)
        Task { [log] in
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
            } catch {
                log.error("Couldn't schedule background refresh: \(error, privacy: .public)")
            }
        }
    }

    private func runBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let sync = Task { [model, log] in
            do {
                try await model.syncAll(prefetch: false)
                task.setTaskCompleted(success: true)
            } catch {
                log.error("Background sync failed: \(error, privacy: .public)")
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { sync.cancel() }
    }
}
