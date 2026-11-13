import Foundation

/// Where a snoozed thread is: out of the Inbox until a time, or back in it since one. Snooze runs on the device,
/// because the Gmail API has none (product brief).
public enum SnoozeState: Equatable, Sendable {
    /// Out of the Inbox until `until`.
    case asleep(until: Date)
    /// Put back in the Inbox at `at`, which the Inbox shows at its top for a while.
    case woke(at: Date)
}

/// The persistence snooze needs. `MailStore` implements it.
public protocol SnoozeStore: Sendable {
    /// Each thread's snooze, for the threads that have one.
    func snoozes(of threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID: SnoozeState]
    /// Sets each thread's snooze; `nil` removes it.
    func setSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?]) throws
    /// Threads asleep until `date` or earlier, soonest first.
    func dueSnoozes(by date: Date) throws -> [ThreadSummary.ID]
    /// When the next asleep thread is due, in any account.
    func nextWakeDate() throws -> Date?
    /// Forgets snoozes that no longer mean anything at `date`: asleep threads put back in the Inbox some other way,
    /// and threads woken long enough ago.
    func pruneSnoozes(at date: Date) throws
}

/// A thread out of the Inbox until `wakeAt`.
public struct SnoozedThread: Equatable, Sendable {
    public var thread: ThreadSummary
    public var wakeAt: Date

    public init(thread: ThreadSummary, wakeAt: Date) {
        self.thread = thread
        self.wakeAt = wakeAt
    }
}
