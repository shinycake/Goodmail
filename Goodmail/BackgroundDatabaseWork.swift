import MailStore
import UIKit

/// Suspends the shared database whenever iOS may suspend the app, and keeps it usable for the work that has background
/// time. iOS kills an app it suspends while it holds a SQLite lock in the App Group container (0xdead10cc): the
/// TestFlight crash of build 1.0 (12), where the cache trim at the end of a foreground sync was mid-write as the
/// reader left the app.
///
/// Work that touches the database outside the foreground runs inside `run(_:_:)`. Anything else that writes then,
/// such as a straggling prefetch, fails with the database suspended rather than getting the app killed.
///
/// One per process, because GRDB suspends and resumes every database in a process together.
final class BackgroundDatabaseWork {
    static let shared = BackgroundDatabaseWork()
    /// How long the database stays usable after the app leaves the foreground with nothing else running.
    private static let leavingTime: Duration = .seconds(5)

    private var suspension: DatabaseSuspension
    /// The background task keeping the app awake for each piece of running work.
    private var tasks: [DatabaseSuspension.Work: UIBackgroundTaskIdentifier] = [:]
    /// Ends the work begun on leaving the foreground, after `leavingTime` or on coming back.
    private var leaving: Task<Void, Never>?

    private init() {
        let launchedInBackground = UIApplication.shared.applicationState == .background
        suspension = DatabaseSuspension(phase: launchedInBackground ? .background : .foreground)
        if suspension.isSuspended { MailDatabase.suspendAll() }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.leaveForeground() }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.enterForeground() }
        }
    }

    /// Runs `operation` with the database usable, and keeps the app awake for it once it leaves the foreground. If the
    /// background time runs out first, the database is suspended under it, so its writes fail instead.
    ///
    /// Nonisolated, so `operation` runs on the caller's isolation (nonisolated async functions don't leave it in
    /// this target); only the bookkeeping hops to the main actor.
    nonisolated func run<T>(_ name: String, _ operation: () async throws -> T) async rethrows -> T {
        let work = await begin(name)
        do {
            let result = try await operation()
            await end(work)
            return result
        } catch {
            await end(work)
            throw error
        }
    }

    /// Writes the reader started just before leaving, such as the draft the composer keeps then or an archive tapped
    /// on the way out, reach the database through actors a moment later. The app stays awake, and the database usable,
    /// for a few seconds more so they land.
    private func leaveForeground() {
        let work = begin("Leaving the foreground")
        update { $0.enter(.background) }
        leaving?.cancel()
        leaving = Task { [weak self] in
            try? await Task.sleep(for: Self.leavingTime)
            self?.end(work)
        }
    }

    private func enterForeground() {
        // Cancelling ends the sleep, so the work begun on leaving ends now.
        leaving?.cancel()
        leaving = nil
        update { $0.enter(.foreground) }
    }

    private func begin(_ name: String) -> DatabaseSuspension.Work {
        let work = update { $0.begin() }
        tasks[work] = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // iOS calls this on the main thread, just before it suspends the app.
            MainActor.assumeIsolated { self?.end(work) }
        }
        return work
    }

    /// Ends `work` once, whether it finished or its time ran out. The database is suspended before the background
    /// task ends, so its locks are gone by the time iOS may suspend the app.
    private func end(_ work: DatabaseSuspension.Work) {
        guard let task = tasks.removeValue(forKey: work) else { return }
        update { $0.end(work) }
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
    }

    /// The one place `suspension` changes, so the database follows it.
    @discardableResult private func update<T>(_ change: (inout DatabaseSuspension) -> T) -> T {
        let wasSuspended = suspension.isSuspended
        let result = change(&suspension)
        switch (wasSuspended, suspension.isSuspended) {
        case (false, true): MailDatabase.suspendAll()
        case (true, false): MailDatabase.resumeAll()
        case (false, false), (true, true): break
        }
        return result
    }
}
