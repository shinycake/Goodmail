import Foundation
import MailCore
import Testing

@testable import MailStore

/// Local search: word prefixes over subject, sender and snippet, merged with the provider's matches.
struct SearchStoreTests {
    private let database: MailDatabase
    private let one = Account(id: AccountID(rawValue: "a1"), email: "one@example.com", color: .teal)
    private let two = Account(id: AccountID(rawValue: "a2"), email: "two@example.com", color: .orange)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SearchStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(one)
        try database.save(two)
    }

    private func thread(
        _ id: String, in account: Account? = nil, minutesAgo: Double = 0, subject: String = "", sender: String = "",
        snippet: String = "", labels: Set<String> = ["INBOX"]
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: (account ?? one).id, threadID: id), subject: subject, snippet: snippet,
            sender: Contact(name: sender, address: "\(id)@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60), isUnread: false, messageCount: 1,
            labelIDs: labels)
    }

    private func search(_ text: String, including ids: [ThreadSummary.ID] = []) async throws -> [String] {
        var iterator = database.search(text, including: ids).makeAsyncIterator()
        return try await iterator.next()?.map(\.id.threadID) ?? []
    }

    @Test func everyWordMatchesAsAPrefixAnywhere() async throws {
        try database.upsert([
            thread("lunch", minutesAgo: 1, subject: "Lunch tomorrow?", sender: "Dana Levi"),
            thread("receipt", minutesAgo: 2, subject: "Your receipt", sender: "Apple", snippet: "Thanks for lunch"),
            thread("hebrew", minutesAgo: 3, subject: "סיכום פגישה", sender: "יעל כהן"),
        ])
        #expect(try await search("lun") == ["lunch", "receipt"])
        #expect(try await search("lunch dana") == ["lunch"])
        #expect(try await search("פגי") == ["hebrew"])
        #expect(try await search("hebrew@example") == ["hebrew"], "the address is searched too")
        #expect(try await search("   ") == [])
    }

    @Test func followsChangesToTheThreads() async throws {
        try database.upsert([thread("t", subject: "Draft agenda")])
        try database.upsert([thread("t", subject: "Final agenda")])
        #expect(try await search("draft") == [])
        #expect(try await search("final") == ["t"])
    }

    @Test func readsTheFiltersItKnows() async throws {
        var unread = thread("unread", minutesAgo: 1, subject: "Dana's notes", sender: "Someone")
        unread.isUnread = true
        try database.upsert([
            unread,
            thread("dana", minutesAgo: 2, subject: "Plans", sender: "Dana Levi", labels: ["INBOX", "STARRED"]),
            thread("other", minutesAgo: 3, subject: "from home"),
        ])
        #expect(try await search("from:dana") == ["dana"])
        #expect(try await search("from:dana@example") == ["dana"], "the address is searched too")
        #expect(try await search("subject:dana") == ["unread"])
        #expect(try await search("is:unread") == ["unread"])
        #expect(try await search("is:read dana") == ["dana"])
        #expect(try await search("is:starred") == ["dana"])
        #expect(try await search("from:\"dana levi\" plans") == ["dana"])
    }

    @Test func leavesWhatItCannotCheckToTheProvider() async throws {
        try database.upsert([thread("attachment", subject: "attachment"), thread("sent", subject: "Plans")])
        let provider = [ThreadSummary.ID(accountID: one.id, threadID: "sent")]
        #expect(try await search("has:attachment") == [])
        #expect(try await search("in:sent plans", including: provider) == ["sent"])
    }

    @Test func providerMatchesJoinTheLocalOnesWithoutSpamOrTrash() async throws {
        try database.upsert([
            thread("local", minutesAgo: 1, subject: "Invoice"),
            thread("body-match", minutesAgo: 2, subject: "March"),
            thread("same-id", in: two, minutesAgo: 3, subject: "March"),
            thread("spam", minutesAgo: 4, subject: "Invoice", labels: ["SPAM"]),
        ])
        let provider = [ThreadSummary.ID(accountID: one.id, threadID: "body-match")]
        #expect(try await search("invoice", including: provider) == ["local", "body-match"])
        #expect(try await search("", including: provider) == ["body-match"])
    }
}
