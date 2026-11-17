import MailCore
import Testing

@testable import MailWrist

/// Quick replies are in the language of the message they answer.
struct WristQuickRepliesTests {
    private func thread(_ bubbles: [(WristBubble.Side, String)], subject: String = "") -> WristThread {
        WristThread(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"), subject: subject,
            bubbles: bubbles.map { WristBubble(side: $0.0, sender: "Noa", time: nil, content: .words($0.1)) },
            earlier: 0, isGroup: false, code: nil)
    }

    @Test func answersHebrewInHebrew() {
        #expect(WristQuickReplies.answers(for: thread([(.theirs, "נתראה מחר?")])) == WristQuickReplies.hebrew)
    }

    @Test func answersTheNewestMessageFromSomeoneElse() {
        let mixed = thread([(.theirs, "See you tomorrow?"), (.mine, "כן")])
        #expect(WristQuickReplies.answers(for: mixed) == WristQuickReplies.english)
    }

    @Test func goesByTheFirstLetterNotDigitsOrPunctuation() {
        #expect(WristQuickReplies.isHebrew("13:00 — מעולה"))
        #expect(!WristQuickReplies.isHebrew("“Great” מעולה"))
    }

    @Test func fallsBackToTheSubject() {
        #expect(WristQuickReplies.answers(for: thread([], subject: "ארוחת צהריים")) == WristQuickReplies.hebrew)
    }
}
