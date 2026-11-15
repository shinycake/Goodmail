import Foundation
import Testing

@testable import MailCore

/// Answering a thread answers its newest message that was sent, never a draft waiting at its end.
struct AnswerTests {
    private let account = AccountID(rawValue: "a")
    private let me = "me@example.com"
    private let dana = Contact(name: "Dana", address: "dana@example.com")
    private let avi = Contact(name: "Avi", address: "avi@example.com")

    private func message(_ id: String, from: Contact, to: [Contact], labels: Set<String> = []) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t1", from: from, to: to,
            subject: "Plan", date: Date(timeIntervalSince1970: 1_791_800_000), labelIDs: labels,
            body: MessageBody(html: nil, plain: "Ship it?"), internetMessageID: "\(id)@example.com")
    }

    private var thread: [Message] {
        [
            message("m1", from: avi, to: [Contact(name: nil, address: me)]),
            message("m2", from: dana, to: [Contact(name: nil, address: me), avi]),
            message("m3", from: Contact(name: nil, address: me), to: [dana], labels: [SystemLabel.draft]),
        ]
    }

    @Test func replyAnswersTheNewestSentMessage() throws {
        let draft = try #require(Answer.reply.draft(answering: thread, accountEmail: me, wording: .english))
        #expect(draft.to == [dana])
        #expect(draft.cc.isEmpty)
        #expect(draft.inReplyTo == "m2@example.com", "the draft at the end is not answered")
    }

    @Test func replyAllCopiesEveryoneElse() throws {
        let draft = try #require(Answer.replyAll.draft(answering: thread, accountEmail: me, wording: .english))
        #expect(draft.to == [dana])
        #expect(draft.cc == [avi])
    }

    @Test func forwardGoesToNobodyYet() throws {
        let draft = try #require(Answer.forward.draft(answering: thread, accountEmail: me, wording: .english))
        #expect(draft.to.isEmpty)
        #expect(draft.subject == "Fwd: Plan")
    }

    @Test func forwardAsAttachmentAttachesTheNewestSentMessage() throws {
        let draft = try #require(
            Answer.forwardAsAttachment.draft(answering: thread, accountEmail: me, wording: .english))
        #expect(draft.subject == "Fwd: Plan")
        #expect(draft.attachments.map(\.content) == [.message(thread[1].id, size: 8)])
    }

    @Test func editAsNewCopiesTheNewestMessageIWrote() throws {
        let mine = message("m0", from: Contact(name: nil, address: "ME@example.com"), to: [avi])
        let draft = try #require(
            Answer.editAsNew.draft(answering: [mine] + thread, accountEmail: me, wording: .english))
        #expect(draft.to == [avi], "m0, not Dana's newer message or the unsent draft")
        let theirs = try #require(Answer.editAsNew.draft(answering: thread, accountEmail: me, wording: .english))
        #expect(theirs.to == thread[1].to, "with none of mine, the newest sent message")
    }

    @Test(arguments: [Answer.reply, .replyAll, .forward, .forwardAsAttachment, .editAsNew])
    func aThreadOfOnlyDraftsHasNothingToAnswer(_ answer: Answer) {
        #expect(answer.draft(answering: Array(thread.suffix(1)), accountEmail: me, wording: .english) == nil)
        #expect(answer.draft(answering: [], accountEmail: me, wording: .english) == nil)
    }
}
