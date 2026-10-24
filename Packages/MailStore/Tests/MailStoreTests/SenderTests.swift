import Foundation
import MailCore
import Testing

@testable import MailStore

/// Messages wait out the undo window, then send once; refused ones stay for the writer, offline ones retry.
struct SenderTests {
    private let database: MailDatabase
    private let server = FakeMailServer()
    private let account = AccountID(rawValue: "a1")
    private let clock = TickingClock(start: Date(timeIntervalSince1970: 1_800_000_000))

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SenderTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(Account(id: account, email: "me@example.com", color: .teal))
    }

    private func commands() -> MailCommands {
        MailCommands(store: database, replay: { _ in }, now: clock.next)
    }

    private func sender() -> Sender {
        Sender(
            accountID: account, provider: server, store: database,
            from: Contact(name: nil, address: "me@example.com"), now: clock.next)
    }

    private func draft(_ subject: String = "Hello") -> Draft {
        Draft(
            accountID: account, to: [Contact(name: nil, address: "dana@example.com")], subject: subject,
            body: MessageBody(html: "<div>Hi</div>", plain: "Hi"), threadID: "t1")
    }

    @Test func messagesWaitOutTheUndoWindow() async throws {
        try commands().send(draft(), after: .seconds(10))
        #expect(await sender().flush().isEmpty)
        #expect(server.sent.isEmpty)
        try commands().send(draft("Now"), after: .zero)
        #expect(await sender().flush().count == 1)
        #expect(server.sent.count == 1)
        #expect(server.sent.first?.threadID == "t1")
        #expect(String(decoding: server.sent[0].raw, as: UTF8.self).contains("Subject: Now"))
    }

    @Test func undoTakesTheDraftBackBeforeItGoes() async throws {
        let draft = draft()
        try commands().send(draft, after: .seconds(10))
        #expect(try commands().cancelSend(draft.id) == draft)
        #expect(try commands().cancelSend(draft.id) == nil)
        #expect(try database.nextSendDate(for: account) == nil)
    }

    @Test func refusedMessagesAreKeptForTheWriter() async throws {
        server.failSend(with: ProviderError.rejected)
        try commands().send(draft(), after: .zero)
        await sender().flush()
        var failed = database.failedMessages().makeAsyncIterator()
        #expect(try await failed.next()?.map(\.draft.subject) == ["Hello"])
        #expect(try database.dueMessages(for: account, by: .distantFuture).isEmpty, "not retried by itself")
    }

    @Test func forwardedFilesAreFetchedWhenTheMessageGoes() async throws {
        let original = Message.ID(accountID: account, messageID: "m1")
        var draft = draft()
        draft.attachments = [
            DraftAttachment(
                filename: "plan.pdf", mimeType: "application/pdf",
                content: .forwarded(
                    Attachment(
                        id: "2", filename: "plan.pdf", mimeType: "application/pdf", size: 5,
                        fetchToken: "att-1"), in: original))
        ]
        try commands().send(draft, after: .zero)
        #expect(await sender().flush().count == 1)
        let raw = String(decoding: server.sent[0].raw, as: UTF8.self)
        #expect(raw.contains(Data("m1/att-1".utf8).base64EncodedString()))
    }

    @Test func aForwardedFileThatIsGoneFailsTheMessage() async throws {
        var draft = draft()
        draft.attachments = [
            DraftAttachment(
                filename: "plan.pdf", mimeType: "application/pdf",
                content: .forwarded(
                    Attachment(id: "2", filename: "plan.pdf", mimeType: "application/pdf", size: 5),
                    in: Message.ID(accountID: account, messageID: "m1")))
        ]
        try commands().send(draft, after: .zero)
        #expect(await sender().flush().isEmpty)
        #expect(server.sent.isEmpty)
        var failed = database.failedMessages().makeAsyncIterator()
        #expect(try await failed.next()?.map(\.failure) == ["A forwarded attachment is no longer available."])
    }

    @Test func offlineMessagesStayQueued() async throws {
        server.failSend(with: URLError(.notConnectedToInternet))
        try commands().send(draft(), after: .zero)
        await sender().flush()
        #expect(try database.dueMessages(for: account, by: .distantFuture).count == 1)
        server.failSend(with: nil)
        #expect(await sender().flush().count == 1)
        #expect(try database.dueMessages(for: account, by: .distantFuture).isEmpty)
    }
}
