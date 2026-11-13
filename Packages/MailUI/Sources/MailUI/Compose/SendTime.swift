import Foundation

/// When a finished message goes: once the undo window closes, or at a time the writer picked.
public enum SendTime: Equatable, Sendable {
    case now
    case at(Date)
}

/// The times the Send menu offers, each with what it is called. A choice that would come too soon to be worth
/// scheduling is left out.
enum SendLaterChoice: Equatable {
    /// 9 PM today.
    case tonight(Date)
    /// 8 AM tomorrow.
    case tomorrowMorning(Date)
    /// 8 AM on the first day after the weekend, offered at the end of the week.
    case nextWeekMorning(Date)

    var date: Date {
        switch self {
        case .tonight(let date), .tomorrowMorning(let date), .nextWeekMorning(let date): date
        }
    }

    var title: String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return switch self {
        case .tonight:
            String(localized: "Tonight, \(time)", bundle: .module, comment: "Send Later choice: this evening")
        case .tomorrowMorning:
            String(localized: "Tomorrow, \(time)", bundle: .module, comment: "Send Later choice: tomorrow morning")
        case .nextWeekMorning:
            String(
                localized: "\(date.formatted(.dateTime.weekday(.wide))), \(time)", bundle: .module,
                comment: "Send Later choice: the first morning after the weekend, as weekday and time")
        }
    }

    /// What to offer at `now`: tonight while there is still an hour before it, tomorrow morning, and the morning
    /// after the weekend from the last day before it until the weekend ends.
    static func choices(at now: Date, calendar: Calendar = .current) -> [SendLaterChoice] {
        var choices: [SendLaterChoice] = []
        let today = calendar.startOfDay(for: now)
        if let tonight = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: today),
            tonight.timeIntervalSince(now) >= 3600
        {
            choices.append(.tonight(tonight))
        }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return choices }
        if let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) {
            choices.append(.tomorrowMorning(morning))
        }
        // The weekend under way, or the one starting tomorrow; the week resumes the day it ends.
        let weekend: DateInterval? =
            if calendar.isDateInWeekend(now) {
                calendar.dateIntervalOfWeekend(containing: now)
            } else if calendar.isDateInWeekend(tomorrow) {
                calendar.dateIntervalOfWeekend(containing: tomorrow)
            } else {
                nil
            }
        if let weekend, calendar.startOfDay(for: weekend.end) != tomorrow,
            let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: weekend.end)
        {
            choices.append(.nextWeekMorning(morning))
        }
        return choices
    }
}
