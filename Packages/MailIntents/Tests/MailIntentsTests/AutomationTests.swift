import Foundation
import MailCore
import Testing

@testable import MailIntents

/// Personal automations run actions with nobody watching: a Find that comes up empty must not stop them, and
/// Check for New Mail hands on what arrived.
struct AutomationTests {
    private let account = Account(
        id: AccountID(rawValue: "A1"), email: "me@example.com", color: .teal, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func thread(_ id: String, minutesAgo: Double, labels: Set<String> = [SystemLabel.inbox]) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "news@shop.com"), date: now - minutesAgo * 60, isUnread: true,
            messageCount: 1, labelIDs: labels)
    }

    @Test func actionsOnNothingFoundDoNothingAndSucceed() async throws {
        let host = FakeHost(accountList: [account])
        let catalog = Catalog(host: host)
        #expect(try await catalog.perform(.archive, onThreads: []).isEmpty)
        #expect(try await catalog.perform(.trash, onMessages: []).isEmpty)
        #expect(try await catalog.pin(true, onThreads: []).isEmpty)
        #expect(try await catalog.snooze([], until: now).isEmpty)
        #expect(try await catalog.move([], to: .trash).isEmpty)
        #expect(try await catalog.messages(ofThreads: [], latestOnly: false).isEmpty)
    }

    @Test func actionsOnMailThatIsGoneStillSaySo() async {
        let catalog = Catalog(host: FakeHost(accountList: [account]))
        await #expect(throws: IntentError.self) { try await catalog.perform(.archive, onThreads: ["nonsense"]) }
        await #expect(throws: IntentError.self) { try await catalog.perform(.trash, onMessages: ["nonsense"]) }
    }

    @Test func newMailIsWhatCameAfterTheNewestBeforeChecking() async throws {
        let host = FakeHost(
            accountList: [account],
            stored: [
                thread("new", minutesAgo: 1), thread("spam", minutesAgo: 2, labels: [SystemLabel.spam]),
                thread("seen", minutesAgo: 10),
            ])
        let found = try await Catalog(host: host).threads(newerThan: now - 5 * 60)
        #expect(found.map(\.title) == ["new"], "newer only, and never Spam")
    }

    @Test func nothingIsNewBeforeTheFirstSync() async throws {
        let host = FakeHost(accountList: [account], stored: [thread("first", minutesAgo: 1)])
        #expect(try await Catalog(host: host).threads(newerThan: nil).isEmpty)
    }
}
