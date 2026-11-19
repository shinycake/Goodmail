import Foundation
import MailCore
import Testing

@testable import MailWrist

/// A conversation squeezed into one WatchConnectivity message: the newest words stay whole longest.
struct WristThreadWireTests {
    private let id = ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t")

    private func letter(_ characters: Int, _ name: String = "x") -> WristBubble {
        WristBubble(
            side: .theirs, sender: "Dana", time: nil,
            content: .letter(
                WristLetter(
                    subject: name, words: StyledText(String(repeating: name, count: characters)), extent: .whole)))
    }

    private func words(_ text: String) -> WristBubble {
        WristBubble(side: .theirs, sender: "Dana", time: nil, content: .words(StyledText(text)))
    }

    private func reply(_ bubbles: [WristBubble]) -> WristThreadReply {
        .thread(WristThread(id: id, subject: "News", bubbles: bubbles, earlier: 0, isGroup: false, code: nil))
    }

    private func sent(_ reply: WristThreadReply, within limit: Int) throws -> (data: Data, thread: WristThread) {
        let data = try reply.encoded(within: limit)
        guard case .thread(let thread) = try JSONDecoder().decode(WristThreadReply.self, from: data) else {
            throw CancellationError()
        }
        return (data, thread)
    }

    @Test func aReplyThatFitsGoesWhole() throws {
        let whole = reply([words("Hi"), letter(5000)])
        #expect(try JSONDecoder().decode(WristThreadReply.self, from: whole.encoded(within: 60_000)) == whole)
    }

    @Test func theOldestLetterIsCutFirst() throws {
        let (data, thread) = try sent(reply([letter(30_000, "o"), letter(30_000, "n")]), within: 40_000)
        #expect(data.count <= 40_000)
        guard case .letter(let oldest) = thread.bubbles[0].content, case .letter(let newest) = thread.bubbles[1].content
        else {
            Issue.record("Expected two letters, got \(thread.bubbles)")
            return
        }
        #expect(oldest.extent == .start)
        #expect(oldest.words.plain.count >= WristThread.shortestCut)
        #expect(
            newest
                == WristLetter(subject: "n", words: StyledText(String(repeating: "n", count: 30_000)), extent: .whole))
    }

    @Test func aLetterTooBigAloneKeepsWhatFits() throws {
        let (data, thread) = try sent(reply([letter(100_000)]), within: 60_000)
        #expect(data.count <= 60_000)
        guard case .letter(let letter) = thread.bubbles[0].content else {
            Issue.record("Expected a letter, got \(thread.bubbles)")
            return
        }
        #expect(letter.extent == .start)
        #expect(letter.words.plain.count > 50_000)
    }

    @Test func aHebrewLetterKeepsAsMuchAsFits() throws {
        let (data, thread) = try sent(reply([letter(40_000, "ש")]), within: 60_000)
        #expect(data.count <= 60_000)
        guard case .letter(let letter) = thread.bubbles[0].content else {
            Issue.record("Expected a letter, got \(thread.bubbles)")
            return
        }
        #expect(letter.extent == .start)
        #expect(letter.words.plain.count > 25_000)
    }

    @Test func onceLettersAreShortTheOldestBubblesAreCounted() throws {
        let many = (0..<12).map { words(String(repeating: "\($0 % 10)", count: 900)) }
        let (data, thread) = try sent(reply(many), within: 5_000)
        #expect(data.count <= 5_000)
        #expect(thread.earlier == 12 - thread.bubbles.count)
        #expect(thread.bubbles.last == many.last)
    }

    @Test func goneTravelsAsIs() throws {
        let gone = WristThreadReply.gone(id)
        #expect(try JSONDecoder().decode(WristThreadReply.self, from: gone.encoded(within: 10)) == gone)
    }
}
