import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailUI

/// A reply on its way, as a thread follows it in either layout: sent at once, overdue later, and replaced by its
/// synced copy. The streams stay open until each test finishes them, as the store's do.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PendingReplyViewTests {
    private let account = AccountID(rawValue: "a")
    private let dana = Contact(name: "Dana", address: "dana@example.com")
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Streams {
        let messages = AsyncThrowingStream<[Message], any Error>.makeStream()
        let queue = AsyncThrowingStream<[OutgoingMessage], any Error>.makeStream()

        func finish() {
            messages.continuation.finish()
            queue.continuation.finish()
        }
    }

    private func model(
        _ streams: Streams, now: @escaping () -> Date,
        attachmentData: @escaping (MailCore.Attachment, Message.ID) async throws -> Data = { _, _ in
            throw ProviderError.notFound
        }
    ) -> ThreadViewModel {
        ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Plan", snippet: "", sender: dana,
                date: start, isUnread: false, messageCount: 1, labelIDs: []),
            mailbox: .inbox, accountEmail: "me@example.com", accountColor: .blue,
            messages: { streams.messages.stream }, outgoing: { streams.queue.stream }, load: {},
            attachmentData: attachmentData, source: { _ in Data() },
            attachmentsDirectory: FileManager.default.temporaryDirectory.appending(path: "Pending-\(UUID())"),
            now: now, layout: .classic)
    }

    private func message(_ id: String, internetID: String? = nil) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t", from: dana, subject: "Plan",
            date: start, labelIDs: ["INBOX"], body: MessageBody(plain: "Text \(id)"),
            internetMessageID: internetID ?? "\(id)@example.com")
    }

    private func reply(files: [DraftAttachment] = []) -> OutgoingMessage {
        OutgoingMessage(
            draft: Draft(
                accountID: account, to: [dana], body: MessageBody(plain: "On my way"), threadID: "t",
                attachments: files),
            sendAt: start)
    }

    /// Waits for `condition`, which the model reaches through its streams and its clock.
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
        #expect(condition())
    }

    @Test func aReplyShowsAsSentAtOnceThenAsSendingOnceOverdue() async throws {
        let streams = Streams()
        let clock = Mutex(start)
        let model = model(streams, now: { clock.withLock { $0 } })
        let observing = Task { await model.observe() }
        streams.messages.continuation.yield([message("1")])
        streams.queue.continuation.yield([reply()])

        try await until { model.replies.map { $0.delivery } == [ChatTranscript.Delivery.sent] }
        clock.withLock { $0 = start.addingTimeInterval(PendingReply.overdueAfter) }
        try await until { model.replies.map { $0.delivery } == [ChatTranscript.Delivery.sending] }

        streams.finish()
        await observing.value
    }

    @Test func aRepliesSyncedCopyOpensAsACardInItsPlace() async throws {
        let streams = Streams()
        let model = model(streams, now: { start })
        let observing = Task { await model.observe() }
        let first = message("1")
        let reply = reply()
        streams.messages.continuation.yield([first])
        streams.queue.continuation.yield([reply])
        try await until { model.replies.count == 1 }

        // The copy syncs as the queue lets the reply go, so the two updates race.
        let copy = message("2", internetID: "<\(reply.headerID)>")
        streams.messages.continuation.yield([first, copy])
        streams.queue.continuation.yield([])
        try await until { model.messages.count == 2 && model.replies.isEmpty }

        #expect(model.expanded.contains(copy.id), "it doesn't fold into a row")
        streams.finish()
        await observing.value
    }

    @Test func aRepliesFilesOpenFromItsDraft() async throws {
        let streams = Streams()
        let model = model(streams, now: { start })
        let observing = Task { await model.observe() }
        let file = DraftAttachment(filename: "plan.txt", mimeType: "text/plain", data: Data("plan".utf8))
        streams.queue.continuation.yield([reply(files: [file])])
        try await until { model.replies.count == 1 }

        let letter = try #require(model.replies.first?.letter)
        let attachment = try #require(letter.attachments.first)
        let url = try await model.file(for: attachment, in: letter.id)
        #expect(try Data(contentsOf: url) == Data("plan".utf8))

        streams.finish()
        await observing.value
    }
}
