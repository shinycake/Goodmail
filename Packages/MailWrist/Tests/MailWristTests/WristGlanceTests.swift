import Foundation
import MailCore
import Testing

@testable import MailWrist

/// The face shows the Inbox at a glance, and the Smart Stack raises it for a fresh code or fresh mail.
struct WristGlanceTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let account = AccountID(rawValue: "a")

    private func row(_ id: String, minutesAgo: Double, unread: Bool = true, code: String? = nil) -> WristRow {
        WristRow(
            id: ThreadSummary.ID(accountID: account, threadID: id),
            sender: Contact(name: "Noa", address: "noa@example.com"), subject: id, snippet: "",
            date: now - minutesAgo * 60, isUnread: unread, messageCount: 1, isPinned: false, code: code)
    }

    private func snapshot(_ rows: [WristRow]) -> WristSnapshot {
        WristSnapshot(
            madeAt: now - 60,
            accounts: [
                WristAccount(
                    id: account, address: "me@example.com", color: .blue, unread: rows.count(where: \.isUnread))
            ],
            rows: rows)
    }

    @Test func waitsForTheIPhone() {
        #expect(WristGlance.timeline(for: nil, now: now) == [WristGlance(date: now, content: .waiting, relevance: 0)])
    }

    @Test func nothingUnreadIsNeverRaised() {
        let read = snapshot([row("a", minutesAgo: 1, unread: false)])
        #expect(
            WristGlance.timeline(for: read, now: now)
                == [WristGlance(date: now, content: .caughtUp(since: now - 60), relevance: 0)])
    }

    @Test func freshMailStepsDownAfterHalfAnHour() {
        let newest = row("new", minutesAgo: 5)
        let timeline = WristGlance.timeline(for: snapshot([row("old", minutesAgo: 90), newest]), now: now)

        #expect(timeline.map(\.date) == [now, now + 25 * 60])
        #expect(timeline.map(\.relevance) == [0.6, 0.2])
        #expect(timeline.allSatisfy { $0.content == .unread(count: 2, newest: newest) })
    }

    @Test func aCodeComesFirstForTenMinutes() {
        let coded = row("code", minutesAgo: 2, code: "482913")
        let timeline = WristGlance.timeline(for: snapshot([coded]), now: now)

        #expect(timeline.map(\.date) == [now, now + 8 * 60, now + 28 * 60])
        #expect(timeline.map(\.relevance) == [1, 0.6, 0.2])
        #expect(timeline[0].content == .code("482913", from: coded, unread: 1))
        #expect(timeline[1].content == .unread(count: 1, newest: coded))
    }

    @Test func aCodeAlreadyReadIsntRaised() {
        let read = snapshot([row("code", minutesAgo: 2, unread: false, code: "482913")])
        #expect(
            WristGlance.timeline(for: read, now: now)
                == [WristGlance(date: now, content: .caughtUp(since: now - 60), relevance: 0)])
    }

    @Test func anOldCodeIsJustMail() {
        let coded = row("code", minutesAgo: 40, code: "482913")
        let timeline = WristGlance.timeline(for: snapshot([coded]), now: now)
        #expect(timeline == [WristGlance(date: now, content: .unread(count: 1, newest: coded), relevance: 0.2)])
    }
}
