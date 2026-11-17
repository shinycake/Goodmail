import Foundation
import MailCore
import Testing

/// Send Later and Snooze offer times worth waiting for, on the iPhone and the watch alike.
struct LaterTimeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // November 2026: the 12th is a Thursday.
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func tonightIsOfferedOnlyWithAnHourToGo() {
        #expect(
            LaterTime.sendChoices(at: date(12, 10), calendar: calendar) == [
                .tonight(date(12, 21)), .tomorrowMorning(date(13, 8)),
            ])
        #expect(LaterTime.sendChoices(at: date(12, 20, 30), calendar: calendar) == [.tomorrowMorning(date(13, 8))])
    }

    @Test func theEndOfTheWeekOffersTheMorningAfterTheWeekend() {
        let friday = LaterTime.sendChoices(at: date(13, 22), calendar: calendar)
        #expect(friday == [.tomorrowMorning(date(14, 8)), .nextWeek(date(16, 8))])
        let saturday = LaterTime.sendChoices(at: date(14, 9), calendar: calendar)
        #expect(saturday == [.tonight(date(14, 21)), .tomorrowMorning(date(15, 8)), .nextWeek(date(16, 8))])
        let sunday = LaterTime.sendChoices(at: date(15, 22), calendar: calendar)
        #expect(sunday == [.tomorrowMorning(date(16, 8))], "tomorrow already starts the week")
    }

    @Test func snoozingOffersTheWeekendOnWeekdays() {
        let thursday = LaterTime.snoozeChoices(at: date(12, 10), calendar: calendar)
        #expect(
            thursday == [
                .thisEvening(date(12, 18)), .tomorrowMorning(date(13, 8)), .thisWeekend(date(14, 8)),
                .nextWeek(date(16, 8)),
            ])
        let friday = LaterTime.snoozeChoices(at: date(13, 17, 30), calendar: calendar)
        #expect(friday == [.tomorrowMorning(date(14, 8)), .nextWeek(date(16, 8))], "the weekend is tomorrow")
    }
}
