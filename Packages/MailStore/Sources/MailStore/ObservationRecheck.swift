import Synchronization

/// Re-runs a database's observations when this process resumes its databases (`MailDatabase.resumeAll()`).
///
/// Another process's write reaches this one's observations only through a re-check (`ChangeSignal`), and a re-check
/// takes the write lock, which a suspended database refuses. So a write the Notification Service Extension signals
/// while the app is suspended, such as the mail it just alerted for, would stay off the app's lists until some later
/// write of the app's own: a refresh then finds nothing newer to fetch, because the extension already moved the
/// cursor past it. Resuming re-checks for whatever was missed.
final class ObservationRecheck: Sendable {
    private static let rechecks = Mutex<[ObjectIdentifier: @Sendable () -> Void]>([:])

    init(_ recheck: @escaping @Sendable () -> Void) {
        Self.rechecks.withLock { $0[ObjectIdentifier(self)] = recheck }
    }

    deinit {
        Self.rechecks.withLock { $0[ObjectIdentifier(self)] = nil }
    }

    /// Runs every open database's re-check.
    static func all() {
        for recheck in rechecks.withLock({ Array($0.values) }) { recheck() }
    }
}
