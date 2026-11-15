import Foundation
import MailCore
import Testing

@testable import MailStore

struct BadgeStoreTests {
    private let database: MailDatabase
    private let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
    private let other = Account(id: AccountID(rawValue: "a2"), email: "me@icloud.com", color: .blue, service: .icloud)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "BadgeStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
        try database.save(other)
        try database.upsert([
            thread("primary"), thread("promo", labels: [SystemLabel.inbox, InboxCategory.promotions.labelID]),
            thread("read", unread: false), thread("archived", labels: []),
            thread("elsewhere", in: other),
        ])
    }

    private func thread(
        _ id: String, in account: Account? = nil, unread: Bool = true, labels: Set<String> = [SystemLabel.inbox]
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: (account ?? self.account).id, threadID: id), subject: "", snippet: "",
            sender: Contact(name: nil, address: "dana@example.com"), date: now, isUnread: unread, messageCount: 1,
            labelIDs: labels)
    }

    @Test func everyAccountCountsItsUnreadInboxUntilTheReaderChooses() throws {
        #expect(try database.badgeSources() == [account.id: .inbox, other.id: .inbox])
        #expect(try database.badgeCount() == 3)
    }

    @Test(arguments: [(BadgeSource.inbox, 3), (.primary, 2), (.off, 1)])
    func eachAccountCountsWhatItsSourceChose(source: BadgeSource, count: Int) throws {
        try database.setBadgeSource(source, for: account.id)
        #expect(try database.badgeSources()[account.id] == source)
        #expect(try database.badgeCount() == count)
    }

    @Test func turningAnAccountsAlertsOffKeepsItOnTheBadge() throws {
        try database.setNotificationLevel(.off, for: account.id, now: now)
        #expect(try database.badgeCount() == 3)
    }

    @Test func theCountFollowsChangesToMailAndChoices() async throws {
        var counts = database.badgeCounts().makeAsyncIterator()
        #expect(try await counts.next() == 3)
        try database.setBadgeSource(.off, for: other.id)
        #expect(try await counts.next() == 2)
        try database.upsert([thread("primary", unread: false)])
        #expect(try await counts.next() == 1)
    }

    @Test func removingTheAccountTakesItsChoiceWithIt() throws {
        try database.setBadgeSource(.off, for: account.id)
        try database.removeAccount(account.id)
        #expect(try database.badgeSources() == [other.id: .inbox])
    }
}
