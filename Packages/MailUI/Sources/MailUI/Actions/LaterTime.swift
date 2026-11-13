import Foundation

/// When a finished message goes: once the undo window closes, or at a time the writer picked.
public enum SendTime: Equatable, Sendable {
    case now
    case at(Date)
}

/// The times offered for sending a message later or snoozing a thread, each with what it is called.
enum LaterTime: Equatable {
    /// 6 PM today.
    case thisEvening(Date)
    /// 9 PM today.
    case tonight(Date)
    /// 8 AM tomorrow.
    case tomorrowMorning(Date)
    /// 8 AM on the first day of the coming weekend.
    case thisWeekend(Date)
    /// 8 AM on the first day after the weekend.
    case nextWeek(Date)

    var date: Date {
        switch self {
        case .thisEvening(let date), .tonight(let date), .tomorrowMorning(let date), .thisWeekend(let date),
            .nextWeek(let date):
            date
        }
    }

    var title: String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return switch self {
        case .thisEvening:
            String(
                localized: "This Evening, \(time)", bundle: .module,
                comment: "Later choice: this evening, with the time")
        case .tonight:
            String(localized: "Tonight, \(time)", bundle: .module, comment: "Later choice: tonight, with the time")
        case .tomorrowMorning:
            String(
                localized: "Tomorrow, \(time)", bundle: .module,
                comment: "Later choice: tomorrow morning, with the time")
        case .thisWeekend, .nextWeek:
            String(
                localized: "\(date.formatted(.dateTime.weekday(.wide))), \(time)", bundle: .module,
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

    /// For sending later: tonight while there is still an hour before it, tomorrow morning, and the morning after
    /// the weekend from the last day before it until the weekend ends.
    static func sendChoices(at now: Date, calendar: Calendar = .current) -> [LaterTime] {
        let days = Days(now: now, calendar: calendar)
        var choices: [LaterTime] = []
        if let tonight = days.today(at: 21), tonight.timeIntervalSince(now) >= 3600 {
            choices.append(.tonight(tonight))
        }
        if let morning = days.tomorrowMorning { choices.append(.tomorrowMorning(morning)) }
        if days.isWeekendNear, let week = days.nextWeekMorning { choices.append(.nextWeek(week)) }
        return choices
    }

    /// For snoozing: this evening while there is still an hour before it, tomorrow morning, the coming weekend on a
    /// weekday before its eve, and the next week.
    static func snoozeChoices(at now: Date, calendar: Calendar = .current) -> [LaterTime] {
        let days = Days(now: now, calendar: calendar)
        var choices: [LaterTime] = []
        if let evening = days.today(at: 18), evening.timeIntervalSince(now) >= 3600 {
            choices.append(.thisEvening(evening))
        }
        if let morning = days.tomorrowMorning { choices.append(.tomorrowMorning(morning)) }
        if !days.isWeekendNear, let weekend = days.weekendMorning { choices.append(.thisWeekend(weekend)) }
        if let week = days.nextWeekMorning { choices.append(.nextWeek(week)) }
        return choices
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

/// The days the later choices are reckoned from, in the reader's calendar and its weekend.
private struct Days {
    let now: Date
    let calendar: Calendar
    let today: Date
    let tomorrow: Date?

    init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
    }

    func today(at hour: Int) -> Date? {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today)
    }

    var tomorrowMorning: Date? {
        tomorrow.flatMap { calendar.date(bySettingHour: 8, minute: 0, second: 0, of: $0) }
    }

    /// Whether it is the weekend, or the last day before it.
    var isWeekendNear: Bool {
        calendar.isDateInWeekend(now) || tomorrow.map(calendar.isDateInWeekend) == true
    }

    /// 8 AM on the first day of the next weekend that hasn't begun.
    var weekendMorning: Date? {
        guard let weekend = calendar.nextWeekend(startingAfter: now) else { return nil }
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: weekend.start)
    }

    /// 8 AM on the day the week resumes after the weekend under way or the next one, unless that is tomorrow.
    var nextWeekMorning: Date? {
        let weekend =
            calendar.isDateInWeekend(now)
            ? calendar.dateIntervalOfWeekend(containing: now) : calendar.nextWeekend(startingAfter: now)
        guard let weekend, calendar.startOfDay(for: weekend.end) != tomorrow else { return nil }
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: weekend.end)
    }
}
