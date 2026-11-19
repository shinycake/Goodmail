import Foundation
import MailCore
import Testing

@testable import MailWrist

/// A conversation as the watch reads it: the iPhone's chat bubbles, newest kept, with every word of each message.
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
            id: id, subject: "Lunch", transcript: ChatTranscript(messages: messages, accountEmail: me.address),
            messages: messages)
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

    @Test func wordsAreNeverCut() {
        let long = String(repeating: "word ", count: 190).trimmingCharacters(in: .whitespaces)
        #expect(
            thread([message("1", from: dana, minutes: 0, text: long)]).bubbles.first?.content
                == .words(StyledText(long)))
    }

    @Test func aLongMessageIsALetterWithEveryWord() throws {
        let long = (1...300).map { "Line \($0) of the update." }.joined(separator: "\n")
        let bubble = try #require(thread([message("1", from: dana, minutes: 0, text: long)]).bubbles.first)
        #expect(bubble.content == .letter(WristLetter(subject: "Lunch", words: StyledText(long), extent: .whole)))
    }

    /// A newsletter's own words, not just the preview the chat view shows, links and all.
    @Test func aLaidOutMessageIsALetterWithItsWholeBody() throws {
        var newsletter = message("1", from: dana, minutes: 0)
        newsletter.body = MessageBody(
            html: "<table><tr><td><table><tr><td>Weekly news</td></tr></table></td></tr></table>"
                + "<p>Read <a href=\"https://example.com/a\">the story</a></p>")
        let bubble = try #require(thread([newsletter]).bubbles.first)
        guard case .letter(let letter) = bubble.content else {
            Issue.record("Expected a letter, got \(bubble.content)")
            return
        }
        #expect(letter.words.plain == "Weekly news\nRead the story")
        #expect(letter.words.runs.contains { $0.link == URL(string: "https://example.com/a") })
        #expect(letter.extent == .whole)
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
        #expect(
            thread([message("1", from: dana, minutes: 0, text: words)]).bubbles.first?.content
                == .words(StyledText(words)))
    }

    @Test func repliesTravelAndReadBack() throws {
        let reply = WristThreadReply.thread(thread([message("1", from: dana, minutes: 0)]))
        #expect(try JSONDecoder().decode(WristThreadReply.self, from: JSONEncoder().encode(reply)) == reply)
        #expect(reply.id == id)
        #expect(WristThreadReply.gone(id).id == id)
    }
}
