import Foundation
import MailCore
import Testing

@testable import MailStore

/// Mailboxes other than the Inbox: All Mail, per-account user labels, and the counts the mailbox list shows.
struct MailboxStoreTests {
    private let database: MailDatabase
    private let one = Account(id: AccountID(rawValue: "a1"), email: "one@example.com", color: .teal, service: .gmail)
    private let two = Account(id: AccountID(rawValue: "a2"), email: "two@example.com", color: .orange, service: .gmail)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MailboxStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(one)
        try database.save(two)
    }

    private func thread(
        _ id: String, in account: Account? = nil, minutesAgo: Double = 0, unread: Bool = false, labels: Set<String>
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: (account ?? one).id, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "\(id)@example.com"),
            date: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60), isUnread: unread, messageCount: 1,
            labelIDs: labels)
    }

    private func first<Value>(_ stream: AsyncThrowingStream<Value, any Error>) async throws -> Value? {
        var iterator = stream.makeAsyncIterator()
        return try await iterator.next()
    }

    private func ids(in mailbox: Mailbox) async throws -> [String] {
        try await first(database.threads(in: mailbox))?.map(\.id.threadID) ?? []
    }

    @Test func allMailIsEverythingButSpamAndTrash() async throws {
        try database.upsert([
            thread("inbox", minutesAgo: 1, labels: ["INBOX"]),
            thread("archived", minutesAgo: 2, labels: []),
            thread("spam", minutesAgo: 3, labels: ["SPAM"]),
            thread("binned", minutesAgo: 4, labels: ["TRASH", "STARRED"]),
        ])
        #expect(try await ids(in: .allMail) == ["inbox", "archived"])
        #expect(try await ids(in: .trash) == ["binned"])
        #expect(try await ids(in: .starred) == ["binned"])
        for thread in try await first(database.threads(in: .allMail)) ?? [] {
            #expect(Mailbox.allMail.contains(thread))
        }
    }

    @Test func aUserLabelStaysInItsAccount() async throws {
        try database.upsert([
            thread("mine", minutesAgo: 1, labels: ["Label_1"]),
            thread("theirs", in: two, minutesAgo: 2, labels: ["Label_1"]),
        ])
        #expect(try await ids(in: Mailbox(labelID: "Label_1", accountID: one.id)) == ["mine"])
        #expect(try await ids(in: Mailbox(labelID: "Label_1")) == ["mine", "theirs"])
    }

    @Test func theDirectoryListsVisibleUserLabelsWithUnreadCounts() async throws {
        try database.apply(
            StoreChanges(
                accountID: one.id,
                labels: [
                    MailLabel(id: "INBOX", name: "INBOX", kind: .system),
                    MailLabel(id: "Label_2", name: "travel", kind: .user, color: "#16a765"),
                    MailLabel(id: "Label_1", name: "Receipts", kind: .user),
                    MailLabel(id: "Label_3", name: "Hidden", kind: .user, isHidden: true),
                ]))
        try database.upsert([
            thread("a", unread: true, labels: ["INBOX", "Label_1"]),
            thread("b", unread: true, labels: ["INBOX"]),
            thread("c", unread: false, labels: ["INBOX", "Label_1"]),
            thread("d", in: two, unread: true, labels: ["INBOX"]),
            thread("e", unread: true, labels: ["SPAM"]),
        ])

        let directory = try #require(try await first(database.mailboxDirectory()))
        #expect(directory.labels.map(\.name) == ["Receipts", "travel"], "by name, ignoring case; hidden ones left out")
        #expect(directory.labels.last?.color == "#16a765")
        #expect(directory.unreadCounts[.inbox] == 3, "the Inbox blends both accounts")
        #expect(directory.unreadCounts[Mailbox(labelID: "INBOX", accountID: one.id)] == 2, "and counts in each")
        #expect(directory.unreadCounts[Mailbox(labelID: "INBOX", accountID: two.id)] == 1)
        #expect(directory.unreadCounts[Mailbox(labelID: "Label_1")] == nil, "a user label isn't blended")
        #expect(directory.unreadCounts[Mailbox(labelID: "Label_1", accountID: one.id)] == 1)
        #expect(directory.unreadCounts[.allMail] == 3, "spam isn't counted in All Mail")
        #expect(directory.unreadCounts[.spam] == 1)
    }
}
