import Foundation
import MailCore
import Testing

struct PendingRepliesTests {
    private let account = AccountID(rawValue: "a")
    private let me = Contact(name: "Me", address: "me@example.com")
    private let dana = Contact(name: "Dana", address: "dana@example.com")
    private let start = Date(timeIntervalSince1970: 1_791_800_000)

    private func outgoing(
        _ text: String, id: UUID = UUID(), purpose: OutgoingMessage.Purpose = .send, minutes: Double = 0,
        delivery: OutgoingMessage.Delivery = .queued, attachments: [DraftAttachment] = []
    ) -> OutgoingMessage {
        OutgoingMessage(
            draft: Draft(
                id: id, accountID: account, to: [dana], body: MessageBody(plain: text), threadID: "t",
                attachments: attachments),
            purpose: purpose, sendAt: start.addingTimeInterval(minutes * 60), delivery: delivery)
    }

    private func synced(_ id: String, from: Contact, minutes: Double, internetID: String? = nil) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t", from: from,
            to: [from == me ? dana : me], subject: "Lunch", date: start.addingTimeInterval(minutes * 60),
            snippet: "", labelIDs: [], body: MessageBody(plain: "Text \(id)"), attachments: [],
            internetMessageID: internetID ?? "\(id)@example.com", references: [])
    }

    private func updated(
        _ pending: inout PendingReplies, queue: [OutgoingMessage], takenBack: Set<Draft.ID> = [],
        conversation: [Message] = [], now: Date? = nil
    ) -> [ChatTranscript.Delivery] {
        pending.update(
            queue: queue, takenBack: takenBack, conversation: conversation, accountEmail: me.address,
            now: now ?? start)
        return pending.replies.map(\.delivery)
    }

    @Test(arguments: [
        (OutgoingMessage.Delivery.queued, ChatTranscript.Delivery.sending),
        (.uploading(UploadID()), .sending),
        (.failed(.rejected), .failed(.rejected)),
    ])
    func aQueuedReplyShowsHowFarItGot(queued: OutgoingMessage.Delivery, shown: ChatTranscript.Delivery) {
        var pending = PendingReplies()
        #expect(updated(&pending, queue: [outgoing("Hi", delivery: queued)]) == [shown])
    }

    @Test func aScheduledReplyWaitsUntilItsTimeThenSends() {
        let later = outgoing("Later", purpose: .scheduledSend, minutes: 60)
        var pending = PendingReplies()
        #expect(updated(&pending, queue: [later]) == [.scheduled(later.sendAt)])
        #expect(updated(&pending, queue: [later], now: later.sendAt) == [.sending])
    }

    @Test func draftSavesAreNotReplies() {
        var pending = PendingReplies()
        #expect(updated(&pending, queue: [outgoing("Draft", purpose: .saveDraft)]).isEmpty)
    }

    @Test func aReplyThatLeftTheQueueStaysAsSentUntilItsCopySyncs() throws {
        let reply = outgoing("Hi")
        var pending = PendingReplies()
        _ = updated(&pending, queue: [reply])
        #expect(updated(&pending, queue: []) == [.sent])
        let copy = synced("s", from: me, minutes: 0, internetID: "<\(reply.headerID)>")
        #expect(updated(&pending, queue: [], conversation: [copy]).isEmpty)
    }

    @Test func aReplyTakenBackDisappears() {
        let reply = outgoing("Oops")
        var pending = PendingReplies()
        _ = updated(&pending, queue: [reply])
        #expect(updated(&pending, queue: [], takenBack: [reply.id]).isEmpty)
    }

    @Test func anUnscheduledReplyBecomesADraftAndDisappears() {
        let id = UUID()
        var pending = PendingReplies()
        _ = updated(&pending, queue: [outgoing("Later", id: id, purpose: .scheduledSend, minutes: 60)])
        #expect(updated(&pending, queue: [outgoing("Later", id: id, purpose: .saveDraft)]).isEmpty)
    }

    @Test func aReplyAlreadySyncedIsNotPending() {
        let reply = outgoing("Hi")
        var pending = PendingReplies()
        let copy = synced("s", from: me, minutes: 0, internetID: reply.headerID)
        #expect(updated(&pending, queue: [reply], conversation: [copy]).isEmpty)
    }

    @Test func scheduledRepliesComeAfterTheOnesThatGoNow() {
        let scheduled = outgoing("Tomorrow", purpose: .scheduledSend, minutes: 60 * 24)
        let first = outgoing("First", minutes: 1)
        let second = outgoing("Second", minutes: 2)
        var pending = PendingReplies()
        _ = updated(&pending, queue: [scheduled, second, first])
        #expect(pending.replies.map(\.id) == [first.id, second.id, scheduled.id])
    }

    // MARK: In the transcript

    private func transcript(_ messages: [Message], pending queue: [OutgoingMessage]) -> ChatTranscript {
        var pending = PendingReplies()
        pending.update(queue: queue, takenBack: [], conversation: messages, accountEmail: me.address, now: start)
        return ChatTranscript(messages: messages, accountEmail: me.address, pending: pending.replies)
    }

    private func runs(_ transcript: ChatTranscript) -> [ChatTranscript.Run] {
        transcript.entries.compactMap { if case .run(let run) = $0 { run } else { nil } }
    }

    @Test func aPendingReplyJoinsMyRunAtTheEnd() throws {
        let reply = outgoing("On my way", minutes: 2)
        let chat = transcript(
            [synced("1", from: dana, minutes: 0), synced("2", from: me, minutes: 1)], pending: [reply])
        let run = try #require(runs(chat).last)
        #expect(run.side == .mine)
        #expect(
            run.bubbles.map(\.origin) == [.message(Message.ID(accountID: account, messageID: "2")), .pending(reply.id)])
        #expect(run.bubbles.last?.content == .words([.text("On my way")], replyingTo: nil))
        #expect(run.bubbles.map(\.delivery) == [.sent, .sending])
    }

    @Test func aPendingReplyCarriesItsFilesAsBubbles() throws {
        let file = DraftAttachment(filename: "plan.pdf", mimeType: "application/pdf", data: Data(count: 10))
        let chat = transcript([synced("1", from: dana, minutes: 0)], pending: [outgoing("See", attachments: [file])])
        let run = try #require(runs(chat).last)
        #expect(run.side == .mine)
        #expect(run.bubbles.count == 2)
        guard case .attachment(let shown) = run.bubbles.last?.content else {
            Issue.record("expected an attachment bubble")
            return
        }
        #expect(shown.filename == "plan.pdf")
        #expect(shown.size == 10)
    }

    @Test func aScheduledReplyAddsNoTimestamp() {
        let later = outgoing("Tomorrow", purpose: .scheduledSend, minutes: 60 * 24)
        let chat = transcript([synced("1", from: dana, minutes: 0)], pending: [later])
        #expect(chat.entries.filter { if case .timestamp = $0 { true } else { false } }.count == 1)
        #expect(runs(chat).map(\.side) == [.theirs, .mine])
    }

    @Test func aReplyAfterALongPauseGetsItsTimestamp() {
        let chat = transcript([synced("1", from: dana, minutes: 0)], pending: [outgoing("Sorry, late", minutes: 120)])
        #expect(chat.entries.filter { if case .timestamp = $0 { true } else { false } }.count == 2)
    }
}
