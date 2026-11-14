import Foundation
import MailCore
import Testing

@testable import MailUI

struct ChatTimestampTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Friday, November 13, 2026, 15:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_582_000)

    private func date(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    @Test(arguments: [
        ("2026-11-13T00:00:00Z", "12:00 AM"),
        ("2026-11-13T09:10:00Z", "9:10 AM"),
        ("2026-11-12T23:59:00Z", "Thursday 11:59 PM"),
        ("2026-11-07T00:00:00Z", "Saturday 12:00 AM"),
        ("2026-11-06T23:59:00Z", "Nov 6 at 11:59 PM"),
        ("2026-01-01T08:00:00Z", "Jan 1 at 8:00 AM"),
        ("2025-12-31T23:59:00Z", "Dec 31, 2025 at 11:59 PM"),
    ])
    func readsTheTimeTheWeekdayOrTheDate(_ sent: String, _ expected: String) {
        let text = ChatTimestamp.text(for: date(sent), now: now, calendar: calendar)
        #expect(text.replacing("\u{202F}", with: " ") == expected)
    }
}

@MainActor
struct ChatThreadViewModelTests {
    private let account = AccountID(rawValue: "a")
    private let dana = Contact(name: "Dana", address: "dana@example.com")

    private func model(
        layout: ConversationLayout, messages: [[Message]]
    ) -> ThreadViewModel {
        ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: account, threadID: "t"), subject: "Plan", snippet: "", sender: dana,
                date: .now, isUnread: false, messageCount: 1, labelIDs: []),
            mailbox: .inbox, accountEmail: "me@example.com", accountColor: .blue, accountService: .gmail,
            messages: {
                AsyncThrowingStream { continuation in
                    for batch in messages { continuation.yield(batch) }
                    continuation.finish()
                }
            }, load: {}, attachmentData: { _, _ in Data() }, layout: layout)
    }

    private func message(_ id: String, minutes: Double) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t", from: dana, subject: "Plan",
            date: Date(timeIntervalSince1970: minutes * 60), labelIDs: ["INBOX"], body: MessageBody(plain: "Text \(id)")
        )
    }

    @Test func switchingTheLayoutChangesOnlyThisConversation() {
        let chosen = Preferences.conversationLayout
        let model = model(layout: .classic, messages: [])
        model.switchLayout()
        #expect(model.layout == .chat)
        model.switchLayout()
        #expect(model.layout == .classic)
        #expect(Preferences.conversationLayout == chosen, "the setting stays as the reader chose it")
    }

    @Test func theTranscriptFollowsTheStreamedMessages() async {
        let first = message("1", minutes: 0)
        let model = model(layout: .chat, messages: [[first], [first, message("2", minutes: 1)]])
        await model.observe()
        guard case .run(let run) = model.transcript.entries.last else {
            Issue.record("Expected a run of bubbles")
            return
        }
        #expect(run.bubbles.map(\.message) == [first.id, message("2", minutes: 1).id])
        #expect(!model.transcript.isGroup)
    }
}
