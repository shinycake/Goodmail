import BackgroundTasks
import MailStore
import OSLog
import Synchronization

/// What background app refresh needs of the task iOS hands it. `BGAppRefreshTask` is the real one; the launch tests
/// run the refresh with a stand-in, since only iOS can make a `BGAppRefreshTask`.
nonisolated protocol RefreshTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGAppRefreshTask: RefreshTask {}

/// Background app refresh: a sync without prefetching, asked for again each time by when the next scheduled message
/// or snoozed thread is due.
///
/// Nonisolated, unlike the rest of the app target: iOS calls the launch handler on a background queue, and a handler
/// inferred to be on the main actor traps there (the TestFlight crash of build 1.0 (1)). The sync engines are actors,
/// so the network and database work stays off the main thread; only AppModel's account bookkeeping hops to it.
nonisolated struct BackgroundRefresh: Sendable {
    static let taskID = "com.idanbirman.goodmail.refresh"
    private static let interval: TimeInterval = 15 * 60
    private static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "sync")

    let model: AppModel
    let database: MailDatabase

    /// Call once, before launch finishes: background task handlers must be registered by then. The database may still
    /// be opening, so each refresh waits for `refresh`, and completes at once without one, when it couldn't open.
    static func register(_ refresh: @escaping @Sendable () async -> BackgroundRefresh?) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            run(task, refresh)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        // A scheduled message or snoozed thread due sooner asks for the refresh by its time; iOS still decides when
        // it runs.
        let regular = Date(timeIntervalSinceNow: Self.interval)
        let due = [try? database.nextSendDate(), try? database.nextWakeDate()].compactMap { $0 ?? nil }
        request.earliestBeginDate = min(regular, max(due.min() ?? regular, .now))
        BGTaskScheduler.shared.submitTaskRequest(request) { error in
            guard let error else { return }
            Self.log.error("Couldn't schedule background refresh: \(error, privacy: .public)")
        }
    }

    func run(_ task: any RefreshTask) {
        Self.run(task) { self }
    }

    private static func run(
        _ task: any RefreshTask, _ waitForRefresh: @escaping @Sendable () async -> BackgroundRefresh?
    ) {
        let completion = Completion(task)
        let sync = Task {
            guard let refresh = await waitForRefresh() else { return completion.finish(success: false) }
            refresh.schedule()
            let success = await BackgroundDatabaseWork.shared.run("Background refresh") {
                do {
                    try await refresh.model.syncAll(prefetch: false)
                    return true
                } catch {
                    log.error("Background sync failed: \(error, privacy: .public)")
                    return false
                }
            }
            // After the database is suspended again: completing lets iOS suspend the app.
            completion.finish(success: success)
        }
        // Out of time: the task is completed now, not when the cancelled sync gets round to returning, since iOS
        // ends an app that holds an expired task. The sync's own background task keeps the app awake while it
        // unwinds, and suspends the database under it if that runs out too.
        task.expirationHandler = {
            sync.cancel()
            completion.finish(success: false)
        }
    }
}

/// Completes the task once: when the sync ends, or when iOS says its time is up, whichever comes first.
///
/// `@unchecked Sendable` because `BGTask` isn't marked `Sendable`, though it is documented as safe to complete from
/// any thread. Safe: `task` is never changed, and `completed` lets only the first `finish` through to it.
private nonisolated final class Completion: @unchecked Sendable {
    private let task: any RefreshTask
    private let completed = Atomic(false)

    init(_ task: any RefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        guard !completed.exchange(true, ordering: .acquiringAndReleasing) else { return }
        task.setTaskCompleted(success: success)
    }
}
