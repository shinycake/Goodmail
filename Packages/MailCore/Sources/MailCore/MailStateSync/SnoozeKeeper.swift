public import Foundation

/// Which of the reader's devices answers for a snoozed thread when its time comes (ADR-037). The device that snoozed
/// it alerts and wakes it on time. Every other device took the snooze up from the shared mail state: it doesn't
/// alert, and it wakes the thread only once `fallbackDelay` has passed with the thread still asleep, which covers a
/// keeper that is off, asleep or suspended without waking it twice whenever the keeper is there.
public enum SnoozeKeeper: String, Sendable {
    case thisDevice
    case otherDevice

    /// How long another device waits past a snooze's time for its keeper to wake it and share that.
    public static let fallbackDelay: TimeInterval = 15 * 60

    /// When this device puts back a thread asleep until `until`.
    public func wakeTime(for until: Date) -> Date {
        switch self {
        case .thisDevice: until
        case .otherDevice: until.addingTimeInterval(Self.fallbackDelay)
        }
    }

    /// Whether this device alerts when the thread wakes.
    public var alerts: Bool {
        switch self {
        case .thisDevice: true
        case .otherDevice: false
        }
    }
}
