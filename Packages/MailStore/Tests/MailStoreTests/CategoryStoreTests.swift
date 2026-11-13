import Foundation
import MailCore
import Testing

@testable import MailStore

struct CategoryStoreTests {
    private let database: MailDatabase
    private let home = AccountID(rawValue: "home")
    private let work = AccountID(rawValue: "work")

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "CategoryStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(Account(id: home, email: "home@example.com", color: .teal, service: .gmail))
        try database.save(Account(id: work, email: "work@example.com", color: .orange, service: .gmail))
        try database.upsert([
            thread("personal", labels: ["INBOX", "CATEGORY_PERSONAL"]),
            thread("uncategorized", labels: ["INBOX"], isUnread: false),
            thread("sale", labels: ["INBOX", "CATEGORY_PROMOTIONS"]),
            thread("friend", labels: ["INBOX", "CATEGORY_SOCIAL"]),
            thread("receipt", labels: ["INBOX", "CATEGORY_UPDATES"]),
            thread("list", labels: ["INBOX", "CATEGORY_FORUMS"], isUnread: false),
            thread("archived sale", labels: ["CATEGORY_PROMOTIONS"]),
            thread("spam", labels: ["SPAM", "CATEGORY_PROMOTIONS"]),
            thread("work newsletter", account: work, labels: ["INBOX", "CATEGORY_PROMOTIONS"]),
            thread("work note", account: work, labels: ["INBOX"]),
        ])
    }

    private func thread(
        _ id: String, account: AccountID? = nil, labels: Set<String>, isUnread: Bool = true
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account ?? home, threadID: id),
            subject: id, snippet: "", sender: Contact(name: nil, address: "x@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - Double(id.count) * 60),
            isUnread: isUnread, messageCount: 1, labelIDs: labels)
    }

    private func inbox(_ category: InboxCategory, unsorted: Set<AccountID> = []) async throws -> Set<String> {
        var iterator = database.threads(in: .inbox, category: category, unsorted: unsorted).makeAsyncIterator()
        return Set(try await iterator.next()?.map(\.id.threadID) ?? [])
    }

    @Test func eachCategoryHoldsItsOwnInboxThreads() async throws {
        #expect(try await inbox(.promotions) == ["sale", "work newsletter"], "archived and spam stay out")
        #expect(try await inbox(.social) == ["friend"])
        #expect(try await inbox(.updates) == ["receipt"])
        #expect(try await inbox(.forums) == ["list"])
    }

    @Test func primaryHoldsThreadsWithoutAnotherCategory() async throws {
        #expect(try await inbox(.primary) == ["personal", "uncategorized", "work note"])
    }

    @Test func anUnsortedAccountKeepsItsWholeInboxInPrimary() async throws {
        #expect(
            try await inbox(.primary, unsorted: [work]) == [
                "personal", "uncategorized", "work note", "work newsletter",
            ])
        #expect(try await inbox(.promotions, unsorted: [work]) == ["sale"])
    }

    @Test func unreadCountsArePerCategory() async throws {
        var iterator = database.categoryUnreadCounts(in: .inbox).makeAsyncIterator()
        #expect(try await iterator.next() == [.primary: 2, .promotions: 2, .social: 1, .updates: 1])

        var unsorted = database.categoryUnreadCounts(in: .inbox, unsorted: [work]).makeAsyncIterator()
        #expect(try await unsorted.next() == [.primary: 3, .promotions: 1, .social: 1, .updates: 1])
    }

    @Test func aThreadMovesWhenItsCategoryChanges() async throws {
        var iterator = database.threads(in: .inbox, category: .social).makeAsyncIterator()
        #expect(try await iterator.next()?.map(\.id.threadID) == ["friend"])
        try database.upsert([thread("sale", labels: ["INBOX", "CATEGORY_SOCIAL"])])
        #expect(Set(try await iterator.next()?.map(\.id.threadID) ?? []) == ["friend", "sale"])
    }
}
