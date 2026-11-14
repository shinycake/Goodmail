import Foundation
import MailCore
import Testing

struct ChatTranscriptTests {
    private let account = AccountID(rawValue: "a")
    private let me = Contact(name: "Me", address: "me@example.com")
    private let dana = Contact(name: "Dana Levi", address: "dana@example.com")
    private let avi = Contact(name: "Avi", address: "avi@example.com")
    private let start = Date(timeIntervalSince1970: 1_791_800_000)

    private func message(
        _ id: String, from: Contact, to: [Contact]? = nil, minutes: Double, body: MessageBody? = nil,
        labels: Set<String> = [], attachments: [MailCore.Attachment] = [], inReplyTo: String? = nil
    ) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t", from: from,
            to: to ?? [from == me ? dana : me], subject: "Lunch", date: start.addingTimeInterval(minutes * 60),
            snippet: "snippet \(id)", labelIDs: labels, body: body ?? MessageBody(plain: "Text \(id)"),
            attachments: attachments, internetMessageID: "\(id)@example.com",
            references: inReplyTo.map { ["\($0)@example.com"] } ?? [])
    }

    private func transcript(_ messages: [Message]) -> ChatTranscript {
        ChatTranscript(messages: messages, accountEmail: "ME@example.com")
    }

    private func runs(_ transcript: ChatTranscript) -> [ChatTranscript.Run] {
        transcript.entries.compactMap { if case .run(let run) = $0 { run } else { nil } }
    }

    @Test func consecutiveMessagesFromOneSenderShareARun() {
        let chat = transcript([
            message("1", from: dana, minutes: 0), message("2", from: dana, minutes: 2),
            message("3", from: me, minutes: 5), message("4", from: dana, minutes: 6),
        ])
        #expect(runs(chat).map(\.side) == [.theirs, .mine, .theirs])
        #expect(runs(chat).map(\.bubbles.count) == [2, 1, 1])
        #expect(runs(chat).first?.sender == dana)
    }

    @Test func myMessagesAreTheAccountsOwnOrSent() {
        let alias = Contact(name: "Me", address: "me@alias.example.com")
        let chat = transcript([message("1", from: alias, minutes: 0, labels: [SystemLabel.sent])])
        #expect(runs(chat).map(\.side) == [.mine])
        #expect(!chat.isGroup, "an alias is me, not another person")
    }

    @Test func aLongPauseStartsANewRunUnderATimestamp() {
        let chat = transcript([message("1", from: dana, minutes: 0), message("2", from: dana, minutes: 90)])
        #expect(chat.entries.count == 4)
        #expect(chat.entries.first == .timestamp(start))
        #expect(chat.entries[2] == .timestamp(start.addingTimeInterval(90 * 60)))
    }

    @Test func unsentDraftsAreLeftOut() {
        let chat = transcript([
            message("1", from: dana, minutes: 0), message("2", from: me, minutes: 1, labels: [SystemLabel.draft]),
        ])
        #expect(runs(chat).count == 1)
    }

    @Test func bubblesHoldTheNewWordsOnly() throws {
        let body = MessageBody(plain: "Noon works.\n\nOn Monday, Dana <dana@example.com> wrote:\n> Lunch?")
        let chat = transcript([message("1", from: me, minutes: 0, body: body)])
        let bubble = try #require(runs(chat).first?.bubbles.first)
        #expect(bubble.content == .words([.text("Noon works.")], replyingTo: nil))
    }

    @Test func aReplyToAnOlderMessageQuotesIt() throws {
        let chat = transcript([
            message("1", from: dana, minutes: 0, body: MessageBody(plain: "Lunch at noon?\nOr later?")),
            message("2", from: avi, minutes: 1),
            message("3", from: me, minutes: 2, inReplyTo: "1"),
        ])
        let reply = try #require(runs(chat).last?.bubbles.first)
        let quote = ChatTranscript.Quote(
            message: Message.ID(accountID: account, messageID: "1"), sender: dana, side: .theirs,
            excerpt: "Lunch at noon?")
        #expect(reply.content == .words([.text("Text 3")], replyingTo: quote))
    }

    @Test func aReplyToTheMessageJustAboveNeedsNoQuote() throws {
        let chat = transcript([
            message("1", from: dana, minutes: 0), message("2", from: me, minutes: 1, inReplyTo: "1"),
        ])
        let reply = try #require(runs(chat).last?.bubbles.first)
        #expect(reply.content == .words([.text("Text 2")], replyingTo: nil))
    }

    @Test func attachmentsFollowTheirMessageAsBubbles() {
        let file = MailCore.Attachment(id: "2", filename: "Plan.pdf", mimeType: "application/pdf", size: 10)
        let logo = MailCore.Attachment(id: "3", filename: "logo.png", mimeType: "image/png", size: 1, isInline: true)
        let chat = transcript([message("1", from: dana, minutes: 0, attachments: [file, logo])])
        #expect(
            runs(chat).first?.bubbles.map(\.content) == [.words([.text("Text 1")], replyingTo: nil), .attachment(file)])
    }

    @Test func aMessageWithOnlyAnAttachmentIsJustTheAttachment() {
        let file = MailCore.Attachment(id: "2", filename: "Plan.pdf", mimeType: "application/pdf", size: 10)
        let chat = transcript([message("1", from: dana, minutes: 0, body: MessageBody(plain: ""), attachments: [file])])
        #expect(runs(chat).first?.bubbles.map(\.content) == [.attachment(file)])
    }

    @Test(arguments: [
        MessageBody(plain: String(repeating: "A long paragraph. ", count: 80)),
        MessageBody(html: "<table><tr><td><table><tr><td>Sale ends today</td></tr></table></td></tr></table>"),
        MessageBody(plain: "---------- Forwarded message ---------\nFrom: Dana\n\nThe report."),
    ])
    func longLaidOutOrEmptyMailIsALetter(_ body: MessageBody) {
        let chat = transcript([message("1", from: dana, minutes: 0, body: body)])
        guard case .letter(let subject, let preview) = runs(chat).first?.bubbles.first?.content else {
            Issue.record("Expected a letter")
            return
        }
        #expect(subject == "Lunch")
        #expect(!preview.isEmpty)
    }

    @Test func aConversationWithMoreThanOneOtherPersonIsAGroup() {
        let pair = transcript([message("1", from: dana, minutes: 0), message("2", from: me, minutes: 1)])
        let group = transcript([message("1", from: dana, to: [me, avi], minutes: 0)])
        #expect(pair.others == [dana])
        #expect(!pair.isGroup)
        #expect(group.others == [dana, avi])
        #expect(group.isGroup)
    }
}
