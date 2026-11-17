public import Foundation
import MailCore

/// When a finished message goes: once the undo window closes, or at a time the writer picked.
public enum SendTime: Equatable, Sendable {
    case now
    case at(Date)
}

extension LaterTime {
    var title: String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return switch self {
        case .thisEvening:
            String(
                localized: "This Evening, \(time)", table: "Actions", bundle: .module,
                comment: "Later choice: this evening, with the time")
        case .tonight:
            String(
                localized: "Tonight, \(time)", table: "Actions", bundle: .module,
                comment: "Later choice: tonight, with the time")
        case .tomorrowMorning:
            String(
                localized: "Tomorrow, \(time)", table: "Actions", bundle: .module,
                comment: "Later choice: tomorrow morning, with the time")
        case .thisWeekend, .nextWeek:
            String(
                localized: "\(date.formatted(.dateTime.weekday(.wide))), \(time)", table: "Actions", bundle: .module,
                comment: "Later choice: a morning on another day, as weekday and time")
        }
    }

    var symbol: String {
        switch self {
        case .thisEvening, .tonight: "moon"
        case .tomorrowMorning: "sunrise"
        case .thisWeekend: "sofa"
        case .nextWeek: "briefcase"
        }
    }
}

/// How a later time reads, for a scheduled message or a snoozed thread: "Today at 9:00 PM", "Tomorrow at
/// 8:00 AM", then a date.
enum ScheduledTime {
    static func text(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
