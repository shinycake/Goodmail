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

    @Test(arguments: [OutgoingMessage.Delivery.queued, .uploading(UploadID())])
    func aReplyOnItsWayReadsAsSentUntilItIsOverdue(delivery: OutgoingMessage.Delivery) {
        let reply = outgoing("Hi", delivery: delivery)
        var pending = PendingReplies()
        #expect(updated(&pending, queue: [reply]) == [.sent])
        let overdue = reply.sendAt.addingTimeInterval(PendingReply.overdueAfter)
        #expect(updated(&pending, queue: [reply], now: overdue.addingTimeInterval(-1)) == [.sent])
        #expect(updated(&pending, queue: [reply], now: overdue) == [.sending])
    }

    @Test func aFailedReplySaysSo() {
        var pending = PendingReplies()
        #expect(updated(&pending, queue: [outgoing("Hi", delivery: .failed(.rejected))]) == [.failed(.rejected)])
    }

    @Test func aScheduledReplyWaitsUntilItsTimeThenSends() {
        let later = outgoing("Later", purpose: .scheduledSend, minutes: 60)
        var pending = PendingReplies()
        #expect(updated(&pending, queue: [later]) == [.scheduled(later.sendAt)])
        #expect(updated(&pending, queue: [later], now: later.sendAt) == [.sent])
        #expect(
            updated(&pending, queue: [later], now: later.sendAt.addingTimeInterval(PendingReply.overdueAfter))
                == [.sending])
    }

    @Test func theNextChangeIsWhenAReplyGoesOrIsOverdue() {
        let now = outgoing("Now", minutes: 0)
        let later = outgoing("Later", purpose: .scheduledSend, minutes: 60)
        var pending = PendingReplies()
        _ = updated(&pending, queue: [now, later])
        let overdue = now.sendAt.addingTimeInterval(PendingReply.overdueAfter)
        #expect(pending.nextChange(after: start) == overdue)
        #expect(pending.nextChange(after: overdue) == later.sendAt)
        _ = updated(&pending, queue: [])
        #expect(pending.nextChange(after: start) == nil, "replies that went don't change with the time")
    }

    @Test func aFailedReplyDoesntChangeWithTheTime() {
        var pending = PendingReplies()
        _ = updated(&pending, queue: [outgoing("Hi", delivery: .failed(.rejected))])
        #expect(pending.nextChange(after: start) == nil)
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
        #expect(pending.replies.map(\.phase) == [.gone])
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

    // MARK: In the classic layout

    @Test func aReplyReadsAsALetterWithWhatItSends() throws {
        let file = DraftAttachment(filename: "plan.pdf", mimeType: "application/pdf", data: Data(count: 10))
        var message = outgoing("See you", attachments: [file])
        message.draft.subject = "Re: Lunch"
        message.draft.quote = MessageBody(plain: "> Lunch?")
        let reply = PendingReply(message, accountEmail: me.address, now: start)

        let letter = reply.letter
        #expect(letter.id == reply.letterID)
        #expect(letter.from == Contact(name: nil, address: me.address))
        #expect(letter.to == [dana])
        #expect(letter.subject == "Re: Lunch")
        #expect(letter.date == message.sendAt)
        #expect(letter.body.plain == "See you\n\n> Lunch?")
        #expect(letter.internetMessageID == message.headerID)
        let attachment = try #require(letter.attachments.first)
        #expect(attachment.filename == "plan.pdf")
        #expect(reply.data(for: attachment) == Data(count: 10))
    }

    @Test func aSyncedCopyTakesItsRepliesPlace() {
        let reply = outgoing("Hi")
        var pending = PendingReplies()
        _ = updated(&pending, queue: [reply])
        let copy = synced("s", from: me, minutes: 0, internetID: "<\(reply.headerID)>")
        let other = synced("o", from: dana, minutes: 0)
        #expect(pending.copies(in: [other, copy]) == [copy.id])
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
        #expect(run.bubbles.map(\.delivery) == [.sent, .sent])
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
