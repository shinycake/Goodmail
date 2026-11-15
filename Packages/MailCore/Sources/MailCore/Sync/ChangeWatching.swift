/// A provider whose server reports changes as they happen, as an IMAP server in IDLE does, so the app can sync at
/// once instead of at the next poll.
public protocol ChangeWatching: Sendable {
    /// Calls `changed` each time the server reports a change, and after each time it connects, for what changed
    /// while nothing was watching, until the calling task is cancelled. Returns when the server can't report
    /// changes, which leaves the account to polling. Throws `CancellationError` once cancelled, and the errors that
    /// trying again won't fix, such as a refused password.
    func watchChanges(_ changed: @escaping @Sendable () async -> Void) async throws
}
