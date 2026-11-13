import Foundation
import MailCore
import Testing

@testable import MailStore

struct MessageStoreTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private var threadID: ThreadSummary.ID { ThreadSummary.ID(accountID: account.id, threadID: "t1") }

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MessageStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
        try database.upsert([
            ThreadSummary(
                id: threadID, subject: "s", snippet: "", sender: Contact(name: nil, address: "a@example.com"),
                date: .now, isUnread: true, messageCount: 2, labelIDs: ["INBOX"])
        ])
    }

    private func message(_ id: String, minutes: Double, html: String) -> Message {
        Message(
            id: Message.ID(accountID: account.id, messageID: id),
            threadID: "t1",
            from: Contact(name: "יעל כהן", address: "yael@example.co.il"),
            subject: "סיכום",
            date: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60),
            labelIDs: ["INBOX", "UNREAD"],
            body: MessageBody(html: html, plain: nil),
            attachments: [Attachment(id: "1", filename: "הצעה.pdf", mimeType: "application/pdf", size: 10)]
        )
    }

    private func stored() async throws -> [Message] {
        var iterator = database.messages(inThread: threadID).makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    @Test func messagesRoundTripOldestFirst() async throws {
        let later = message("m2", minutes: 5, html: "<div dir=\"rtl\">תשובה</div>")
        let earlier = message("m1", minutes: 0, html: "<p>first</p>")
        try database.save([later, earlier], inThread: threadID)
        #expect(try await stored() == [earlier, later])
    }

    @Test func aDraftsBccIsStoredAndReopens() async throws {
        var draft = message("d1", minutes: 0, html: "<p>hi</p>")
        draft.labelIDs = ["DRAFT"]
        draft.to = [Contact(name: nil, address: "dana@example.com")]
        draft.cc = [Contact(name: nil, address: "avi@example.com")]
        draft.bcc = [Contact(name: "Boss", address: "boss@example.com")]
        try database.save([draft], inThread: threadID)
        let stored = try #require(try await stored().first)
        #expect(stored.bcc == draft.bcc)
        let reopened = Draft.editing(stored)
        #expect(reopened.bcc == draft.bcc)
        #expect(reopened.cc == draft.cc)
    }

    @Test func savingAgainReplacesTheThreadsMessages() async throws {
        try database.save(
            [message("m1", minutes: 0, html: "a"), message("m2", minutes: 1, html: "b")], inThread: threadID)
        try database.save([message("m1", minutes: 0, html: "edited")], inThread: threadID)
        #expect(try await stored().map(\.body.html) == ["edited"])
    }

    @Test func deletingTheThreadDeletesItsMessages() async throws {
        try database.save([message("m1", minutes: 0, html: "a")], inThread: threadID)
        try database.apply(StoreChanges(accountID: account.id, deletions: ["t1"]))
        #expect(try await stored().isEmpty)
    }
}
