import Foundation
import MailCore

/// "Days Old": how many whole days have passed since mail arrived, so Find can ask for "older than a week" without a
/// date worked out first. Each comparison becomes a date range read against now, which the store narrows by.
enum DaysOld {
    static let day: TimeInterval = 86_400

    /// The whole days from `date` to `now`; mail from the future is 0 days old.
    static func of(_ date: Date, now: Date) -> Int {
        max(0, Int((now.timeIntervalSince(date) / day).rounded(.down)))
    }

    /// Mail at least `days` days old.
    static func atLeast(_ days: Int, now: Date = .now) -> MailCondition {
        .date(.date, .before(now.addingTimeInterval(-Double(days) * day)))
    }

    /// Mail at most `days` days old: less than `days + 1` whole days.
    static func atMost(_ days: Int, now: Date = .now) -> MailCondition {
        .date(.date, .after(now.addingTimeInterval(-Double(days + 1) * day)))
    }

    static func exactly(_ days: Int, now: Date = .now) -> MailCondition {
        between(days, days, now: now)
    }

    static func between(_ low: Int, _ high: Int, now: Date = .now) -> MailCondition {
        .all([atLeast(min(low, high), now: now), atMost(max(low, high), now: now)])
    }
}
