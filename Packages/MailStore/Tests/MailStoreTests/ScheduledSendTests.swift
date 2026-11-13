import Foundation
import MailCore
import Testing

@testable import MailStore

/// A message scheduled for later waits, listed under Scheduled, until its time; taken back, it goes to Drafts.
struct ScheduledSendTests {
    private let database: MailDatabase
    private let server = FakeMailServer()
    private let account = AccountID(rawValue: "a1")
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ScheduledSendTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(Account(id: account, email: "me@example.com", color: .teal, service: .gmail))
    }

    private func commands(at date: Date) -> MailCommands {
        MailCommands(store: database, replay: { _ in }, now: { date })
    }

    private func sender(at date: Date) -> Sender {
        Sender(accountID: account, provider: server, store: database, now: { date })
    }

    private func draft(_ subject: String) -> Draft {
        Draft(
            accountID: account, to: [Contact(name: nil, address: "dana@example.com")], subject: subject,
            body: MessageBody(html: nil, plain: "Hi"))
    }

    @Test func aScheduledMessageGoesOnlyOnceItsTimeComes() async throws {
        let sendAt = start.addingTimeInterval(3 * 3600)
        try commands(at: start).schedule(draft("Later"), at: sendAt)

        #expect(await sender(at: sendAt.addingTimeInterval(-1)).flush().isEmpty)
        #expect(server.sent.isEmpty)
        #expect(try database.nextSendDate() == sendAt)

        #expect(await sender(at: sendAt).flush().map(\.subject) == ["Later"])
        #expect(server.sent.count == 1)
        #expect(try database.nextSendDate() == nil)
    }

    @Test func scheduledListsOnlyMessagesWaitingForAPickedTime() async throws {
        let commands = commands(at: start)
        try commands.schedule(draft("Friday"), at: start.addingTimeInterval(86400))
        try commands.schedule(draft("Tonight"), at: start.addingTimeInterval(3600))
        try commands.send(draft("Undo window"), after: .seconds(10))
        try commands.saveDraft(draft("Saved"))

        var scheduled = database.scheduledMessages().makeAsyncIterator()
        #expect(try await scheduled.next()?.map(\.draft.subject) == ["Tonight", "Friday"])
        var directory = database.mailboxDirectory().makeAsyncIterator()
        #expect(try await directory.next()?.scheduledCount == 2)
    }

    @Test func unschedulingKeepsTheMessageInDrafts() async throws {
        let message = draft("Maybe")
        try commands(at: start).schedule(message, at: start.addingTimeInterval(3600))
        try commands(at: start).unschedule(message.id)

        var scheduled = database.scheduledMessages().makeAsyncIterator()
        #expect(try await scheduled.next()?.isEmpty == true)
        #expect(await sender(at: start).flush().map(\.subject) == ["Maybe"])
        #expect(server.sent.isEmpty)
        #expect(server.drafts.count == 1)
    }

    @Test func aRefusedScheduledMessageLeavesScheduledForFailures() async throws {
        server.failSend(with: ProviderError.rejected)
        try commands(at: start).schedule(draft("Refused"), at: start)
        await sender(at: start).flush()

        var scheduled = database.scheduledMessages().makeAsyncIterator()
        #expect(try await scheduled.next()?.isEmpty == true)
        var failed = database.failedMessages().makeAsyncIterator()
        #expect(try await failed.next()?.map(\.purpose) == [.scheduledSend])
    }
}
