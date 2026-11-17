public import Foundation

/// When the watch next asks the system for time to check its own mail in the background (ADR-023). The system
/// decides when it really runs; this only keeps the asks to a budget a day of battery can afford.
public enum WristRefreshPlan {
    /// How long after a check the next is asked for.
    public static let interval: TimeInterval = 15 * 60

    /// The time to ask for after a check that ended at `lastRun`, or `nil` to ask for none, as in Low Power Mode,
    /// where the watch checks only while the app is open.
    public static func next(after lastRun: Date, lowPower: Bool) -> Date? {
        lowPower ? nil : lastRun.addingTimeInterval(interval)
    }
}
