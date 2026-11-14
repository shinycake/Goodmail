import Foundation

/// The quiet time-of-day sections of a mailbox list, newest first.
nonisolated public enum TimeSection: Hashable, Sendable {
    case thisMorning
    case thisAfternoon
    case thisEvening
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case month(year: Int, month: Int)

    /// Sections only ever get older down the list, as long as items are sorted newest first.
    public static func section(for date: Date, now: Date, calendar: Calendar) -> TimeSection {
        if date >= calendar.startOfDay(for: now) {
            switch calendar.component(.hour, from: min(date, now)) {
            case ..<12: return .thisMorning
            case ..<17: return .thisAfternoon
            default: return .thisEvening
            }
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return .yesterday
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return .thisWeek
        }
        if let aWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
            calendar.isDate(date, equalTo: aWeekAgo, toGranularity: .weekOfYear)
        {
            return .lastWeek
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return .thisMonth
        }
        let components = calendar.dateComponents([.year, .month], from: date)
        return .month(year: components.year ?? 0, month: components.month ?? 0)
    }

    /// Consecutive runs of `items` that fall in the same section. `items` must be sorted newest first.
    public static func group<Item>(
        _ items: [Item],
        by date: (Item) -> Date,
        now: Date,
        calendar: Calendar
    ) -> [(section: TimeSection, items: [Item])] {
        var groups: [(section: TimeSection, items: [Item])] = []
        for item in items {
            let section = section(for: date(item), now: now, calendar: calendar)
            if groups.last?.section == section {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((section, [item]))
            }
        }
        return groups
    }

    public func title(now: Date, calendar: Calendar) -> String {
        switch self {
        case .thisMorning:
            String(localized: "This morning", table: "Mailbox", bundle: .module, comment: "Mailbox section header")
        case .thisAfternoon:
            String(localized: "This afternoon", table: "Mailbox", bundle: .module, comment: "Mailbox section header")
        case .thisEvening:
            String(localized: "This evening", table: "Mailbox", bundle: .module, comment: "Mailbox section header")
        case .yesterday:
            String(localized: "Yesterday", table: "Mailbox", bundle: .module, comment: "Mailbox section header")
        case .thisWeek:
            String(localized: "This week", table: "Mailbox", bundle: .module, comment: "Mailbox section header")
        case .lastWeek:
            String(localized: "Last week", table: "Mailbox", bundle: .module, comment: "Mailbox section header")
        case .thisMonth:
            String(localized: "This month", table: "Mailbox", bundle: .module, comment: "Mailbox section header")
        case .month(let year, let month):
            Self.monthTitle(year: year, month: month, now: now, calendar: calendar)
        }
    }

    private static func monthTitle(year: Int, month: Int, now: Date, calendar: Calendar) -> String {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return "" }
        var style = Date.FormatStyle(
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone
        )
        .month(.wide)
        if year != calendar.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }
}

/// The date at a row's trailing edge: a time today, a weekday this past week, otherwise a short date.
nonisolated public enum RowDate {
    public static func text(for date: Date, now: Date, calendar: Calendar) -> String {
        let base = Date.FormatStyle(
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(base.hour().minute())
        }
        if let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)),
            date >= sixDaysAgo
        {
            return date.formatted(base.weekday(.abbreviated))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(base.day().month(.abbreviated))
        }
        return date.formatted(base.day().month(.abbreviated).year())
    }
}
