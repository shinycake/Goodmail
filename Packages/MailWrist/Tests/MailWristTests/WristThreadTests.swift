import Foundation
import MailCore
import Testing

@testable import MailWrist

/// A conversation as the watch reads it: the iPhone's chat bubbles, newest kept, small enough to send.
struct WristThreadTests {
    private let account = AccountID(rawValue: "a")
    private let me = Contact(name: "Me", address: "me@example.com")
    private let dana = Contact(name: "Dana Levi", address: "dana@example.com")
    private let avi = Contact(name: "Avi", address: "avi@example.com")
    private let start = Date(timeIntervalSince1970: 1_791_800_000)
    private var id: ThreadSummary.ID { ThreadSummary.ID(accountID: account, threadID: "t") }

    private func message(_ id: String, from: Contact, minutes: Double, text: String? = nil) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t", from: from,
            to: [from == me ? dana : me], subject: "Lunch", date: start.addingTimeInterval(minutes * 60),
            snippet: "", labelIDs: [], body: MessageBody(plain: text ?? "Text \(id)"), attachments: [],
            internetMessageID: "\(id)@example.com", references: [])
    }

    private func thread(_ messages: [Message]) -> WristThread {
        WristThread(
            id: id, subject: "Lunch", transcript: ChatTranscript(messages: messages, accountEmail: me.address))
    }

    @Test func bubblesKeepTheirSideSenderAndWords() {
        let thread = thread([message("1", from: dana, minutes: 0), message("2", from: me, minutes: 2)])
        #expect(
            thread.bubbles == [
                WristBubble(side: .theirs, sender: "Dana Levi", time: start, content: .words("Text 1")),
                WristBubble(side: .mine, sender: "Me", time: nil, content: .words("Text 2")),
            ])
        #expect(thread.earlier == 0)
        #expect(!thread.isGroup)
    }

    @Test func aPauseShowsTheTimeAgain() {
        let thread = thread([message("1", from: dana, minutes: 0), message("2", from: dana, minutes: 120)])
        #expect(thread.bubbles.map(\.time) == [start, start.addingTimeInterval(7200)])
    }

    @Test func keepsTheNewestBubblesAndCountsTheRest() {
        let messages = (0..<20).map { message("\($0)", from: $0.isMultiple(of: 2) ? dana : me, minutes: Double($0)) }
        let thread = thread(messages)
        #expect(thread.bubbles.count == WristThread.bubbleLimit)
        #expect(thread.earlier == 20 - WristThread.bubbleLimit)
        #expect(thread.bubbles.last?.content == .words("Text 19"))
    }

    @Test func groupsNameTheirSenders() {
        #expect(thread([message("1", from: dana, minutes: 0), message("2", from: avi, minutes: 1)]).isGroup)
    }

    @Test func longWordsAreCut() throws {
        let long = String(repeating: "word ", count: 190)
        let bubble = try #require(thread([message("1", from: dana, minutes: 0, text: long)]).bubbles.first)
        guard case .words(let words) = bubble.content else {
            Issue.record("Expected words, got \(bubble.content)")
            return
        }
        #expect(words.count == WristThread.wordsLimit)
    }

    @Test func findsTheCodeInTheirNewestWords() {
        let thread = thread([
            message("1", from: me, minutes: 0, text: "Can you send the code?"),
            message("2", from: dana, minutes: 1, text: "Your verification code is 482913."),
        ])
        #expect(thread.code == "482913")
    }

    @Test func hebrewStaysIntact() {
        let words = "מעולה. אזמין שולחן לארבעה."
        #expect(thread([message("1", from: dana, minutes: 0, text: words)]).bubbles.first?.content == .words(words))
    }

    @Test func repliesTravelAndReadBack() throws {
        let reply = WristThreadReply.thread(thread([message("1", from: dana, minutes: 0)]))
        #expect(try JSONDecoder().decode(WristThreadReply.self, from: JSONEncoder().encode(reply)) == reply)
        #expect(reply.id == id)
        #expect(WristThreadReply.gone(id).id == id)
    }
}
