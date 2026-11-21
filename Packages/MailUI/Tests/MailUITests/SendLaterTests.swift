import Foundation
import MailCore
import Testing

@testable import MailUI

/// A scheduled message can be taken back or kept in Drafts.
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

    @Test func schedulingConfirmsAndCanBeTakenBack() async throws {
        let store = OutgoingQueue()
        let actions = MailActions(commands: MailCommands(store: store, replay: { _ in }), toastDuration: .seconds(60))
        var reopened: [Draft] = []
        actions.reopen = { reopened.append($0) }
        let draft = Draft(accountID: AccountID(rawValue: "a"), subject: "Later")

        actions.send(draft, at: .at(date(13, 8)))
        await actions.settled()
        #expect(store.messages.map(\.purpose) == [.scheduledSend])
        #expect(actions.toast?.message.hasPrefix("Scheduled for") == true)
        actions.undoLast()
        await actions.settled()
        #expect(store.messages.isEmpty)
        #expect(reopened == [draft])

        actions.send(draft, at: .at(date(13, 8)))
        actions.unschedule(draft.id)
        await actions.settled()
        #expect(store.messages.map(\.purpose) == [.saveDraft], "kept in Drafts")
    }
}

/// The send queue in memory.
final class OutgoingQueue: MailCommands.Store, @unchecked Sendable {
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
    func uploadingMessages(for account: AccountID) throws -> [OutgoingMessage] { [] }
    func update(_ id: Draft.ID, from expected: OutgoingMessage.Delivery, to message: OutgoingMessage?) throws -> Bool {
        false
    }
    func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage? {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return nil }
        messages[index].purpose = purpose
        messages[index].sendAt = date
        return messages[index]
    }
    func remove(_ id: Draft.ID) throws { messages.removeAll { $0.id == id } }
    func enqueueSave(_ message: OutgoingMessage) throws { messages.append(message) }
    func finish(_ message: OutgoingMessage) throws -> Bool {
        guard messages.contains(message) else { return false }
        messages.removeAll { $0 == message }
        return true
    }
    func savedCopy(of draft: Draft.ID) throws -> Message.ID? { nil }
    func setSavedCopy(_ copy: Message.ID?, of draft: Draft.ID) throws {}
    func sender(for account: AccountID) throws -> Contact { Contact(name: nil, address: "me@example.com") }
    func enqueue(_ intents: [OutboxIntent], account: AccountID) throws -> [String: Set<String>] { [:] }
    func pendingIntents(for account: AccountID) throws -> [OutboxIntent] { [] }
    func markSent(_ id: OutboxIntent.ID, at date: Date) throws {}
    func removeIntent(_ id: OutboxIntent.ID) throws {}
    func snoozes(of threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID: SnoozeState] { [:] }
    func setSnoozes(_ snoozes: [ThreadSummary.ID: SnoozeState?]) throws {}
    func dueSnoozes(by date: Date) throws -> [ThreadSummary.ID] { [] }
    func nextWakeDate() throws -> Date? { nil }
    func pruneSnoozes(at date: Date) throws {}
    func pins(among threads: [ThreadSummary.ID]) throws -> Set<ThreadSummary.ID> { [] }
    func setPins(_ pins: [ThreadSummary.ID: Bool]) throws {}
}
