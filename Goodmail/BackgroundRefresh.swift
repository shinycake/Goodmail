import BackgroundTasks
import MailStore
import OSLog

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

    /// Call once, before launch finishes: background task handlers must be registered by then.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            run(task)
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
        schedule()
        let completion = Completion(task)
        let sync = Task { [model] in
            do {
                try await model.syncAll(prefetch: false)
                completion.finish(success: true)
            } catch {
                Self.log.error("Background sync failed: \(error, privacy: .public)")
                completion.finish(success: false)
            }
        }
        task.expirationHandler = { sync.cancel() }
    }
}

/// Hands the task to the sync that completes it. `BGTask` is documented as safe to complete from any thread, but
/// isn't marked `Sendable`.
private nonisolated final class Completion: @unchecked Sendable {
    private let task: any RefreshTask

    init(_ task: any RefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}
