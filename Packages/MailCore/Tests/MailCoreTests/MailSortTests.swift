import Foundation
import Testing

@testable import MailCore

/// Filters return mail in the order asked, with mail that has no value for a key at the end.
struct MailSortTests {
    static func mail(_ subject: String, body: String, minutesAgo: Double) -> MailFacts {
        MailConditionTests.message(
            subject: subject, body: body, date: MailConditionTests.thursdayNight.addingTimeInterval(-minutesAgo * 60))
    }

    let echo = mail("Echo Dot", body: "Order total: $49.99", minutesAgo: 1)
    let cable = mail("Cable", body: "Order total: $9.99", minutesAgo: 2)
    let note = mail("A note", body: "Thanks!", minutesAgo: 3)

    @Test func byAmountCheapestFirstWithNoAmountLast() {
        let sorted = MailSort.sorted([note, echo, cable], by: [MailSort(.totalAmount, ascending: true)])
        #expect(sorted.map(\.envelope.subject) == ["Cable", "Echo Dot", "A note"])
    }

    @Test func byAmountDearestFirstStillPutsNoAmountLast() {
        let sorted = MailSort.sorted([note, cable, echo], by: [MailSort(.totalAmount, ascending: false)])
        #expect(sorted.map(\.envelope.subject) == ["Echo Dot", "Cable", "A note"])
    }

    @Test func noSortIsNewestFirst() {
        #expect(
            MailSort.sorted([note, cable, echo], by: []).map(\.envelope.subject) == ["Echo Dot", "Cable", "A note"])
    }

    @Test func subjectsSortAsFinderSortsNames() {
        let sorted = MailSort.sorted([echo, note, cable], by: [MailSort(.subject, ascending: true)])
        #expect(sorted.map(\.envelope.subject) == ["A note", "Cable", "Echo Dot"])
    }
}
