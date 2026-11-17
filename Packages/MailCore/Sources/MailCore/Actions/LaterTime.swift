public import Foundation

/// The times offered for sending a message later or snoozing a thread. Each app names them in its own words.
public enum LaterTime: Equatable, Sendable {
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

    public var date: Date {
        switch self {
        case .thisEvening(let date), .tonight(let date), .tomorrowMorning(let date), .thisWeekend(let date),
            .nextWeek(let date):
            date
        }
    }

    /// For sending later: tonight while there is still an hour before it, tomorrow morning, and the morning after
    /// the weekend from the last day before it until the weekend ends.
    public static func sendChoices(at now: Date, calendar: Calendar = .current) -> [LaterTime] {
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
    public static func snoozeChoices(at now: Date, calendar: Calendar = .current) -> [LaterTime] {
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
