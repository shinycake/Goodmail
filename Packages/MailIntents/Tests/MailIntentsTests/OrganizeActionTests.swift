import Foundation
import MailCore
import Testing

@testable import MailIntents

/// Move, snooze and unsubscribe, as the Shortcuts actions run them.
struct OrganizeActionTests {
    private let account = Account(
        id: AccountID(rawValue: "A1"), email: "tester@example.com", color: .teal, service: .gmail)

    private func thread(_ id: String, labels: Set<String>) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Subject \(id)", snippet: "Snippet",
            sender: Contact(name: "Yael", address: "yael@example.com"), date: .now, isUnread: true, messageCount: 1,
            labelIDs: labels)
    }

    private func host(_ threads: ThreadSummary...) -> FakeHost {
        FakeHost(accountList: [account], stored: threads)
    }

    @Test func movingTakesEachConversationOutOfTheMailboxItIsIn() async throws {
        let host = host(
            thread("t1", labels: [SystemLabel.inbox]), thread("t2", labels: [SystemLabel.spam]),
            thread("t3", labels: [SystemLabel.inbox]))
        let changes = try await Catalog(host: host).move(["A1/t1", "A1/t2", "A1/t3"], to: .label("Receipts"))
        #expect(host.performed.on("t1") == [.move(to: .label("Receipts"), from: .inbox)])
        #expect(host.performed.on("t2") == [.move(to: .label("Receipts"), from: Mailbox(labelID: SystemLabel.spam))])
        #expect(host.performed.on("t3") == host.performed.on("t1"))
        #expect(changes.count == 2, "one change per mailbox moved out of")
    }

    @Test func movingNothingStillOnTheDeviceFails() async {
        await #expect(throws: IntentError.self) {
            try await Catalog(host: host()).move(["A1/gone"], to: .archive)
        }
    }

    @Test func snoozingAsksForTheWakeDateAndUnsnoozingForNone() async throws {
        let host = host(thread("t1", labels: [SystemLabel.inbox]))
        let wake = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await Catalog(host: host).snooze(["A1/t1"], until: wake)
        _ = try await Catalog(host: host).snooze(["A1/t1"], until: nil)
        #expect(host.performed.snoozes(of: "t1") == [wake, nil])
    }

    @Test func snoozingNothingFails() async {
        await #expect(throws: IntentError.self) { try await Catalog(host: host()).snooze(["nonsense"], until: .now) }
    }

    @Test(arguments: [
        (Duration.seconds(90), 90.0), (.days(14), 1_209_600.0), (.milliseconds(1500), 1.5),
    ])
    func aDurationIsItsWholeLengthInSeconds(duration: Duration, seconds: TimeInterval) {
        #expect(duration.seconds == seconds)
    }

    @Test func aMessageIsFoundByItsIdentifier() throws {
        var host = host(thread("t1", labels: [SystemLabel.inbox]))
        let list = Unsubscribe.oneClick(URL(string: "https://list.example.com/leave")!)
        host.cached[ThreadSummary.ID(accountID: account.id, threadID: "t1")] = [
            Message(
                id: Message.ID(accountID: account.id, messageID: "m1"), threadID: "t1",
                from: Contact(name: "List", address: "news@example.com"), to: [], subject: "News", date: .now,
                labelIDs: [SystemLabel.inbox], body: MessageBody(html: "<p>News</p>"), unsubscribe: list)
        ]
        let facts = try Catalog(host: host).facts(ofMessage: "A1/t1/m1")
        #expect(facts.content?.unsubscribe == list)
        #expect(throws: IntentError.self) { try Catalog(host: host).facts(ofMessage: "A1/t1/m2") }
    }
}

extension Duration {
    fileprivate static func days(_ days: Int) -> Duration { .seconds(days * 86_400) }
}
