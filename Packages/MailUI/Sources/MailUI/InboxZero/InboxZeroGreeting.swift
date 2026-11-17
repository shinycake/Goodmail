import Foundation

/// The line under "All Caught Up", for the time of day.
nonisolated enum InboxZeroGreeting: Equatable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    /// The greeting for `hour`, 0 to 23. The day parts match the mailbox's time sections, with a night added.
    init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .night
        }
    }

    init(at date: Date, calendar: Calendar = .current) {
        self.init(hour: calendar.component(.hour, from: date))
    }
}
