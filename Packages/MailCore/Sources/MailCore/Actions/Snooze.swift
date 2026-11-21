public import Foundation

/// Where a snoozed thread is: out of the Inbox until a time, or back in it since one. Snooze runs on the device,
/// because the Gmail API has none (product brief), and the reader's devices share it (ADR-037).
public enum SnoozeState: Equatable, Sendable {
    /// Out of the Inbox until `until`, with `keeper` saying whether this device answers for its wake.
    case asleep(until: Date, keeper: SnoozeKeeper)
    /// Put back in the Inbox at `at`, which the Inbox shows at its top for a while.
    case woke(at: Date)
}

/// The persistence snooze needs. `MailStore` implements it.
public protocol SnoozeStore: Sendable {
    /// Each thread's snooze, for the threads that have one.
    func snoozes(of threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID: SnoozeState]
    /// Sets each thread's snooze; `nil` removes it.
    func setSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?]) throws
    /// Threads this device wakes by `date` (`SnoozeKeeper.wakeTime(for:)`), soonest first.
    func dueSnoozes(by date: Date) throws -> [ThreadSummary.ID]
    /// When this device wakes the next asleep thread, in any account.
    func nextWakeDate() throws -> Date?
    /// Forgets snoozes that no longer mean anything at `date`: asleep threads put back in the Inbox some other way
    /// or thrown out to Trash or Spam, and threads woken long enough ago.
    func pruneSnoozes(at date: Date) throws
}

/// A thread out of the Inbox until `wakeAt`, and which device answers for its wake.
public struct SnoozedThread: Equatable, Sendable {
    public var thread: ThreadSummary
    public var wakeAt: Date
    public var keeper: SnoozeKeeper

    public init(thread: ThreadSummary, wakeAt: Date, keeper: SnoozeKeeper) {
        self.thread = thread
        self.wakeAt = wakeAt
        self.keeper = keeper
    }
}
