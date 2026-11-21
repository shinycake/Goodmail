import Foundation
import MailCore
import Testing

@testable import MailStore

/// Which conversations the list can show under With Attachments: those with a downloaded message carrying files.
struct AttachmentThreadsTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AttachmentThreadsTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func thread(_ id: String) throws -> ThreadSummary.ID {
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "a@example.com"), date: .now, isUnread: false, messageCount: 1,
            labelIDs: ["INBOX"])
        try database.upsert([thread])
        return thread.id
    }

    private func message(in thread: ThreadSummary.ID, attachments: [MailCore.Attachment]) -> Message {
        Message(
            id: Message.ID(accountID: account.id, messageID: "m-\(thread.threadID)"), threadID: thread.threadID,
            from: Contact(name: nil, address: "a@example.com"), subject: "s", date: .now, labelIDs: ["INBOX"],
            body: MessageBody(html: "<p>hi</p>", plain: nil), attachments: attachments)
    }

    private func holding() async throws -> Set<ThreadSummary.ID> {
        var iterator = database.threadsHoldingAttachments().makeAsyncIterator()
        return try await iterator.next(isolation: #isolation) ?? []
    }

    @Test func aConversationWithAFileIsFoundAndOneWithPicturesOnlyOrNothingIsNot() async throws {
        let file = try thread("file")
        let picture = try thread("picture")
        let plain = try thread("plain")
        let unopened = try thread("unopened")
        try database.save(
            [
                message(
                    in: file,
                    attachments: [MailCore.Attachment(id: "1", filename: "a.pdf", mimeType: "application/pdf", size: 1)]
                )
            ],
            inThread: file)
        try database.save(
            [
                message(
                    in: picture,
                    attachments: [
                        MailCore.Attachment(
                            id: "1", filename: "logo.png", mimeType: "image/png", size: 1, isInline: true)
                    ])
            ], inThread: picture)
        try database.save([message(in: plain, attachments: [])], inThread: plain)
        _ = unopened
        #expect(try await holding() == [file])
    }
}
