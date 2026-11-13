import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// Messages wait out the undo window, then send once; refused ones stay for the writer, offline ones retry.
/// `BackgroundSendTests` covers the upload's own lifecycle.
struct SenderTests {
    private let bench: SendBench
    private var database: MailDatabase { bench.database }
    private var server: FakeMailServer { bench.server }
    private var account: AccountID { bench.account }

    init() throws {
        bench = try SendBench()
    }

    private func commands() -> MailCommands { bench.commands() }
    private func draft(_ subject: String = "Hello") -> Draft { bench.draft(subject) }

    @Test func messagesWaitOutTheUndoWindow() async throws {
        try await commands().send(draft(), after: .seconds(10))
        #expect(try await bench.deliver().isEmpty)
        #expect(server.sent.isEmpty)
        try await commands().send(draft("Now"), after: .zero)
        #expect(try await bench.deliver().count == 1)
        #expect(server.sent.count == 1)
        #expect(server.sent.first?.threadID == "t1")
        #expect(String(decoding: server.sent[0].raw, as: UTF8.self).contains("Subject: Now"))
    }

    @Test func messagesGoUnderTheAccountsNameAtTheTimeTheyAreSent() async throws {
        let sender = bench.sender()
        try await commands().send(draft("Before"), after: .zero)
        try await bench.deliver(with: sender)
        try database.update(
            Account(id: account, email: "me@example.com", color: .teal, service: .gmail, name: "Dana Levi"))
        try await commands().send(draft("After"), after: .zero)
        try await bench.deliver(with: sender)

        let headers = server.sent.map { String(decoding: $0.raw, as: UTF8.self) }
        #expect(headers[0].contains("From: me@example.com"))
        #expect(headers[1].contains("From: Dana Levi <me@example.com>"))
    }

    @Test func mailFromAnAccountThatCannotBeReadStaysQueued() async throws {
        try await commands().send(draft(), after: .zero)
        try await database.pool.write { db in try db.execute(sql: "DELETE FROM account") }

        #expect(try await bench.deliver().isEmpty)
        #expect(server.sent.isEmpty)
        #expect(try database.dueMessages(for: account, by: .distantFuture).map(\.draft.subject) == ["Hello"])
    }

    @Test func undoTakesTheDraftBackBeforeItGoes() async throws {
        let draft = draft()
        try await commands().send(draft, after: .seconds(10))
        #expect(try await commands().cancelSend(draft.id) == draft)
        #expect(try await commands().cancelSend(draft.id) == nil)
        #expect(try database.nextSendDate(for: account) == nil)
    }

    @Test func refusedMessagesAreKeptForTheWriter() async throws {
        server.answerSends(with: 400)
        try await commands().send(draft(), after: .zero)
        try await bench.deliver()
        #expect(try await bench.failures() == [.rejected])
        #expect(try database.dueMessages(for: account, by: .distantFuture).isEmpty, "not retried by itself")
    }

    @Test func aFailedMessageKeepsItsBccForEditing() async throws {
        var draft = draft()
        draft.cc = [Contact(name: nil, address: "avi@example.com")]
        draft.bcc = [Contact(name: "Boss", address: "boss@example.com")]
        server.answerSends(with: 400)
        try await commands().send(draft, after: .zero)
        try await bench.deliver()
        var failed = database.failedMessages().makeAsyncIterator()
        let reopened = try #require(try await failed.next()?.first?.draft)
        #expect(reopened.bcc == draft.bcc)
        #expect(reopened.cc == draft.cc)
    }

    @Test func savedDraftsCarryTheirBccToTheProvider() async throws {
        var draft = draft()
        draft.bcc = [Contact(name: nil, address: "boss@example.com")]
        try await commands().saveDraft(draft)
        try await bench.deliver()
        let raw = try #require(server.drafts.values.first?.raw)
        #expect(String(decoding: raw, as: UTF8.self).contains("Bcc: boss@example.com"))
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
        try await commands().send(draft, after: .zero)
        #expect(try await bench.deliver().count == 1)
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
        try await commands().send(draft, after: .zero)
        #expect(try await bench.deliver().isEmpty)
        #expect(server.sent.isEmpty)
        #expect(try await bench.failures() == [.forwardedAttachmentMissing])
    }

    @Test func savingADraftReplacesItsCopyAndSendingRemovesIt() async throws {
        try await server.saveDraft(Data(), inThread: "t1", replacing: nil)
        var draft = draft("Plan")
        draft.savedDraft = Message.ID(accountID: account, messageID: "d1")

        try await commands().saveDraft(draft)
        #expect(try await bench.deliver().count == 1)
        #expect(Array(server.drafts.keys) == ["d2"], "d1 was replaced")
        #expect(String(decoding: server.drafts["d2"]!.raw, as: UTF8.self).contains("Subject: Plan"))
        #expect(server.sent.isEmpty)

        draft.savedDraft = Message.ID(accountID: account, messageID: "d2")
        try await commands().send(draft, after: .zero)
        #expect(try await bench.deliver().count == 1)
        #expect(server.sent.count == 1)
        #expect(server.drafts.isEmpty)
    }

    @Test func deletingADraftRemovesOnlyASavedOne() async throws {
        try await server.saveDraft(Data(), inThread: nil, replacing: nil)
        try await commands().deleteDraft(draft())
        #expect(try database.dueMessages(for: account, by: .distantFuture).isEmpty, "never saved: nothing to do")
        var saved = draft()
        saved.savedDraft = Message.ID(accountID: account, messageID: "d1")
        try await commands().deleteDraft(saved)
        #expect(try database.dueMessages(for: account, by: .distantFuture).map(\.purpose) == [.deleteDraft])
        try await bench.deliver()
        #expect(server.drafts.isEmpty)
        #expect(server.sent.isEmpty)
    }

    @Test func aFailedDraftSaveIsRetriedAsASave() async throws {
        try database.enqueue(
            OutgoingMessage(draft: draft(), purpose: .saveDraft, sendAt: .now, delivery: .failed(.rejected)))
        var failures = database.failedMessages().makeAsyncIterator()
        let failed = try #require(try await failures.next()?.first)
        try await commands().retrySend(failed)
        try await bench.deliver()
        #expect(server.drafts.count == 1)
        #expect(server.sent.isEmpty)
    }

    @Test func aFailureStoredAsASentenceByAnEarlierBuildReadsAsRefused() async throws {
        try await commands().send(draft(), after: .zero)
        try await database.pool.write { db in
            try db.execute(sql: "UPDATE outgoing SET failure = 'The server refused the message.'")
        }
        var failed = database.failedMessages().makeAsyncIterator()
        #expect(try await failed.next()?.map(\.failure) == [.rejected])
    }

    @Test func offlineMessagesStayQueued() async throws {
        server.failPrepare(with: URLError(.notConnectedToInternet))
        try await commands().send(draft(), after: .zero)
        try await bench.deliver()
        #expect(try database.dueMessages(for: account, by: .distantFuture).count == 1)
        #expect(bench.uploads.started.isEmpty)
        server.failPrepare(with: nil)
        #expect(try await bench.deliver().count == 1)
        #expect(try database.dueMessages(for: account, by: .distantFuture).isEmpty)
    }

    @Test func removingAnAccountTakesEverythingItHadAndNothingElse() async throws {
        let other = AccountID(rawValue: "a2")
        try database.save(Account(id: other, email: "work@example.com", color: .orange, service: .gmail))
        for id in [account, other] {
            try database.apply(
                StoreChanges(
                    accountID: id,
                    upserts: [
                        ThreadSummary(
                            id: ThreadSummary.ID(accountID: id, threadID: "t1"), subject: "Hi", snippet: "",
                            sender: Contact(name: nil, address: "dana@example.com"), date: .now, isUnread: true,
                            messageCount: 1, labelIDs: ["INBOX"])
                    ],
                    labels: [MailLabel(id: "INBOX", name: "INBOX", kind: .system)], signature: "Me",
                    state: .current(cursor: "1")))
        }
        _ = try await commands().perform(.archive, on: [ThreadSummary.ID(accountID: account, threadID: "t1")])
        try await commands().send(draft(), after: .seconds(60))

        try database.removeAccount(account)

        #expect(try database.accounts().map(\.id) == [other])
        let left = try await database.pool.read { db in
            try ["thread", "threadLabel", "label", "syncState", "outbox", "outgoing"].map { table in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE accountID = ?", arguments: ["a1"])
            }
        }
        #expect(left == [0, 0, 0, 0, 0, 0])
        #expect(try database.thread(ThreadSummary.ID(accountID: other, threadID: "t1")) != nil)
        #expect(try database.signature(for: other) == "Me")
    }
}
