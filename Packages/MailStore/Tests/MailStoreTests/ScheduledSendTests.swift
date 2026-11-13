import Foundation
import MailCore
import Testing

@testable import MailStore

/// A message scheduled for later waits, listed under Scheduled, until its time; taken back, it goes to Drafts.
struct ScheduledSendTests {
    private let bench: SendBench
    private var database: MailDatabase { bench.database }
    private var server: FakeMailServer { bench.server }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        bench = try SendBench()
    }

    private func commands(at date: Date) -> MailCommands {
        MailCommands(store: database, replay: { _ in }, now: { date })
    }

    @discardableResult
    private func deliver(at date: Date) async throws -> [Draft] {
        try await bench.deliver(with: bench.sender(at: date))
    }

    private func draft(_ subject: String) -> Draft {
        Draft(
            accountID: bench.account, to: [Contact(name: nil, address: "dana@example.com")], subject: subject,
            body: MessageBody(html: nil, plain: "Hi"))
    }

    @Test func aScheduledMessageGoesOnlyOnceItsTimeComes() async throws {
        let sendAt = start.addingTimeInterval(3 * 3600)
        try await commands(at: start).schedule(draft("Later"), at: sendAt)

        #expect(try await deliver(at: sendAt.addingTimeInterval(-1)).isEmpty)
        #expect(server.sent.isEmpty)
        #expect(try database.nextSendDate() == sendAt)

        #expect(try await deliver(at: sendAt).map(\.subject) == ["Later"])
        #expect(server.sent.count == 1)
        #expect(try database.nextSendDate() == nil)
    }

    @Test func scheduledListsOnlyMessagesWaitingForAPickedTime() async throws {
        let commands = commands(at: start)
        try await commands.schedule(draft("Friday"), at: start.addingTimeInterval(86400))
        try await commands.schedule(draft("Tonight"), at: start.addingTimeInterval(3600))
        try await commands.send(draft("Undo window"), after: .seconds(10))
        try await commands.saveDraft(draft("Saved"))

        var scheduled = database.scheduledMessages().makeAsyncIterator()
        #expect(try await scheduled.next()?.map(\.draft.subject) == ["Tonight", "Friday"])
        var directory = database.mailboxDirectory().makeAsyncIterator()
        #expect(try await directory.next()?.scheduledCount == 2)
    }

    @Test func unschedulingKeepsTheMessageInDrafts() async throws {
        let message = draft("Maybe")
        try await commands(at: start).schedule(message, at: start.addingTimeInterval(3600))
        try await commands(at: start).unschedule(message.id)

        var scheduled = database.scheduledMessages().makeAsyncIterator()
        #expect(try await scheduled.next()?.isEmpty == true)
        #expect(try await deliver(at: start).map(\.subject) == ["Maybe"])
        #expect(server.sent.isEmpty)
        #expect(server.drafts.count == 1)
    }

    @Test func unschedulingAMessageThatAlreadyWentDoesNothing() async throws {
        let message = draft("Gone")
        try await commands(at: start).schedule(message, at: start)
        try await deliver(at: start)
        try await commands(at: start).unschedule(message.id)

        #expect(try database.requeue(message.id, as: .saveDraft, at: start) == nil)
        #expect(try await deliver(at: start).isEmpty)
        #expect(server.sent.count == 1)
        #expect(server.drafts.isEmpty, "no draft of a sent message")
    }

    @Test func aRefusedScheduledMessageLeavesScheduledForFailures() async throws {
        server.answerSends(with: 400)
        try await commands(at: start).schedule(draft("Refused"), at: start)
        try await deliver(at: start)

        var scheduled = database.scheduledMessages().makeAsyncIterator()
        #expect(try await scheduled.next()?.isEmpty == true)
        var failed = database.failedMessages().makeAsyncIterator()
        #expect(try await failed.next()?.map(\.purpose) == [.scheduledSend])
    }
}
