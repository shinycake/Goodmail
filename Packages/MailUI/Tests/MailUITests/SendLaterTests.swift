import Foundation
import MailCore
import Testing

@testable import MailUI

/// The Send menu offers times worth waiting for, and a scheduled message can be taken back or kept in Drafts.
@MainActor
struct SendLaterTests {
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
            SendLaterChoice.choices(at: date(12, 10), calendar: calendar) == [
                .tonight(date(12, 21)), .tomorrowMorning(date(13, 8)),
            ])
        #expect(SendLaterChoice.choices(at: date(12, 20, 30), calendar: calendar) == [.tomorrowMorning(date(13, 8))])
    }

    @Test func theEndOfTheWeekOffersTheMorningAfterTheWeekend() {
        let friday = SendLaterChoice.choices(at: date(13, 22), calendar: calendar)
        #expect(friday == [.tomorrowMorning(date(14, 8)), .nextWeekMorning(date(16, 8))])
        let saturday = SendLaterChoice.choices(at: date(14, 9), calendar: calendar)
        #expect(saturday == [.tonight(date(14, 21)), .tomorrowMorning(date(15, 8)), .nextWeekMorning(date(16, 8))])
        let sunday = SendLaterChoice.choices(at: date(15, 22), calendar: calendar)
        #expect(sunday == [.tomorrowMorning(date(16, 8))], "tomorrow already starts the week")
    }

    @Test func schedulingConfirmsAndCanBeTakenBack() throws {
        let store = OutgoingQueue()
        let actions = MailActions(commands: MailCommands(store: store, replay: { _ in }), toastDuration: .seconds(60))
        var reopened: [Draft] = []
        actions.reopen = { reopened.append($0) }
        let draft = Draft(accountID: AccountID(rawValue: "a"), subject: "Later")

        actions.send(draft, at: .at(date(13, 8)))
        #expect(store.messages.map(\.purpose) == [.scheduledSend])
        #expect(actions.toast?.message.hasPrefix("Scheduled for") == true)
        actions.undoLast()
        #expect(store.messages.isEmpty)
        #expect(reopened == [draft])

        actions.send(draft, at: .at(date(13, 8)))
        actions.unschedule(draft.id)
        #expect(store.messages.map(\.purpose) == [.saveDraft], "kept in Drafts")
    }
}

/// The send queue in memory.
private final class OutgoingQueue: OutboxStore, OutgoingStore, @unchecked Sendable {
    var messages: [OutgoingMessage] = []

    func enqueue(_ message: OutgoingMessage) throws {
        messages.removeAll { $0.id == message.id }
        messages.append(message)
    }

    func cancel(_ id: Draft.ID) throws -> OutgoingMessage? {
        defer { messages.removeAll { $0.id == id } }
        return messages.first { $0.id == id }
    }

    func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage] { [] }
    func nextSendDate(for account: AccountID) throws -> Date? { nil }
    func markFailed(_ id: Draft.ID, reason: SendFailure) throws {}
    func remove(_ id: Draft.ID) throws { messages.removeAll { $0.id == id } }
    func sender(for account: AccountID) throws -> Contact { Contact(name: nil, address: "") }
    func enqueue(_ intents: [OutboxIntent], account: AccountID) throws -> [String: Set<String>] { [:] }
    func pendingIntents(for account: AccountID) throws -> [OutboxIntent] { [] }
    func markSent(_ id: OutboxIntent.ID, at date: Date) throws {}
    func removeIntent(_ id: OutboxIntent.ID) throws {}
}
