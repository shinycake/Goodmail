/// When a change watch that ended by itself starts again. A watch already reconnects after a lost connection
/// (`ChangeWatching`); it ends only for what reconnecting won't fix, such as a server that can't IDLE or a refused
/// password. On iOS it stays ended until the app next comes back from the background. A Mac app may run for weeks
/// without that, so there a watch tries again after a minute, then less often, up to once an hour.
public struct WatchRestarts: Sendable {
    private static let first: Duration = .seconds(60)
    private static let longest: Duration = .seconds(60 * 60)

    private let policy: PresencePolicy
    /// Ends in a row, each soon after its start.
    private var ends = 0

    public init(policy: PresencePolicy) {
        self.policy = policy
    }

    /// How long to wait before watching again after a watch that ran for `ran` ended, or nil to leave it ended. A
    /// watch that lasted at least the longest wait has shown it works, so the waits start over.
    public mutating func delay(afterRunning ran: Duration) -> Duration? {
        switch policy {
        case .suspends:
            return nil
        case .keepsRunning:
            ends = ran >= Self.longest ? 1 : ends + 1
            return min(Self.first * (1 << min(ends - 1, 6)), Self.longest)
        }
    }
}

/// Tells that the device slept from a wait that took far longer than asked. Waits are measured on the continuous
/// clock, which counts the time asleep, so a wait that spans a sleep ends on waking. A timer the system merely held
/// back, as App Nap does, runs late by less.
public enum Oversleep {
    private static let slack: Duration = .seconds(60)

    /// Whether a wait of `asked` that took `took` spanned a sleep: more than twice as long, and over a minute late.
    public static func meansTheDeviceSlept(asked: Duration, took: Duration) -> Bool {
        took > asked * 2 && took - asked > slack
    }
}
