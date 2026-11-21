import Foundation
import MailCore
import Testing

@testable import MailStore

/// Smart mailboxes read from the mail on the device: which conversations each holds, its unread count, and the boxes
/// and VIPs the store keeps.
struct SmartMailboxStoreTests {
    private let database: MailDatabase
    private let one = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
    private let two = Account(id: AccountID(rawValue: "a2"), email: "work@example.com", color: .blue, service: .gmail)

    init() throws {
        database = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "SmartMailboxStoreTests-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
        try database.save(one)
        try database.save(two)
    }

    @discardableResult
    private func store(
        _ id: String, in account: Account? = nil, from sender: String = "shop@example.com", minutesAgo: Double = 0,
        unread: Bool = false, labels: Set<String> = [SystemLabel.inbox]
    ) throws -> ThreadSummary {
        let account = account ?? one
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "About \(id)", snippet: "",
            sender: Contact(name: nil, address: sender), date: .now.addingTimeInterval(-minutesAgo * 60),
            isUnread: unread, messageCount: 1, labelIDs: unread ? labels.union([SystemLabel.unread]) : labels)
        try database.upsert([thread])
        return thread
    }

    /// Caches a message of `thread` from `sender`, carrying `attachments`.
    private func cache(_ thread: ThreadSummary, from sender: String, attachments: [MailCore.Attachment] = []) throws {
        let message = Message(
            id: Message.ID(accountID: thread.id.accountID, messageID: "m-\(thread.id.threadID)-\(sender)"),
            threadID: thread.id.threadID, from: Contact(name: nil, address: sender), to: [], subject: thread.subject,
            date: thread.date, labelIDs: thread.labelIDs, body: MessageBody(html: "<p>long</p>", plain: "Hello"),
            attachments: attachments)
        try database.save([message], inThread: thread.id)
    }

    private func first<Value>(_ stream: AsyncThrowingStream<Value, any Error>) async throws -> Value? {
        var iterator = stream.makeAsyncIterator()
        return try await iterator.next(isolation: #isolation)
    }

    private func ids(in box: SmartMailbox) async throws -> [String] {
        try database.saveSmartMailbox(box)
        return try await first(database.threads(inSmartMailbox: box.id))?.map(\.id.threadID) ?? []
    }

    private let pdf = MailCore.Attachment(id: "1", filename: "a.pdf", mimeType: "application/pdf", size: 10)

    @Test func aNewDatabaseStartsWithUnreadVIPsAndAttachments() throws {
        #expect(try database.smartMailboxes() == SmartMailbox.startingSet)
        #expect(try database.vips() == VIPList())
    }

    @Test func aBoxHoldsWhatMeetsItsConditionNewestFirstOutsideSpamAndTrash() async throws {
        try store("old", minutesAgo: 10, unread: true)
        try store("new", minutesAgo: 1, unread: true, labels: [])
        try store("read", minutesAgo: 2)
        try store("spam", minutesAgo: 3, unread: true, labels: [SystemLabel.spam])
        #expect(try await ids(in: SmartMailbox.startingSet[0]) == ["new", "old"])
    }

    @Test func aBoxLeavesOutTheAccountsTheFocusHides() async throws {
        try store("mine", unread: true)
        try store("work", in: two, minutesAgo: 1, unread: true)
        try database.apply(FocusFilter.accounts([one.id]))
        #expect(try await ids(in: SmartMailbox.startingSet[0]) == ["mine"])
    }

    @Test func attachmentsAreKnownFromTheCachedMessages() async throws {
        let files = try store("files")
        try cache(files, from: "shop@example.com", attachments: [pdf])
        let words = try store("words", minutesAgo: 1)
        try cache(words, from: "shop@example.com")
        try store("listed", minutesAgo: 2)
        #expect(try await ids(in: SmartMailbox.startingSet[2]) == ["files"])
    }

    @Test func aConversationStaysWithAVIPAfterTheReaderAnswers() async throws {
        let answered = try store("answered", from: "me@example.com")
        try cache(answered, from: "boss@example.com")
        try store("other", from: "noa@example.com", minutesAgo: 1)
        let vips = SmartMailbox.startingSet[1]
        #expect(try await ids(in: vips).isEmpty, "no VIPs chosen yet")
        try database.setVIP(try #require(SenderAddress("Boss@Example.com")), true)
        #expect(try database.vips().addresses == ["boss@example.com"])
        #expect(try await ids(in: vips) == ["answered"])
    }

    @Test func aMessagesBodyIsReadFromItsPlainText() async throws {
        let hello = try store("hello")
        try cache(hello, from: "shop@example.com")
        try store("silent", minutesAgo: 1)
        let box = SmartMailbox(
            name: .custom("Hello"), symbol: "hand.wave", filter: .condition(.text(.anyText, .contains("hello"))))
        #expect(try await ids(in: box) == ["hello"])
    }

    @Test func theDirectoryCountsEachBoxsUnreadConversations() async throws {
        let files = try store("files", unread: true)
        try cache(files, from: "boss@example.com", attachments: [pdf])
        try store("note", minutesAgo: 1, unread: true)
        try store("read", minutesAgo: 2)
        try database.setVIP(try #require(SenderAddress("boss@example.com")), true)
        let directory = try #require(try await first(database.smartMailboxDirectory()))
        #expect(directory.mailboxes == SmartMailbox.startingSet)
        #expect(
            directory.unreadCounts == [
                SmartMailbox.ID(rawValue: "unread"): 2, .init(rawValue: "vips"): 1, .init(rawValue: "attachments"): 1,
            ])
    }

    @Test func savingKeepsABoxsPlaceAndAddsNewOnesLast() throws {
        var unread = SmartMailbox.startingSet[0]
        unread.name = .custom("New mail")
        try database.saveSmartMailbox(unread)
        let mine = SmartMailbox(name: .custom("Mine"), symbol: "star", filter: .condition(.flag(.starred, true)))
        try database.saveSmartMailbox(mine, vips: VIPList(["dana@example.com"]))
        #expect(
            try database.smartMailboxes().map(\.name) == [
                .custom("New mail"), .vips, .withAttachments, .custom("Mine"),
            ])
        #expect(try database.vips().addresses == ["dana@example.com"])
        try database.deleteSmartMailbox(unread.id)
        #expect(
            try database.smartMailboxes().map(\.id) == [
                SmartMailbox.startingSet[1].id, SmartMailbox.startingSet[2].id, mine.id,
            ])
    }

    @Test func aDeletedBoxShowsNothing() async throws {
        try store("t", unread: true)
        let unread = SmartMailbox.startingSet[0]
        try database.deleteSmartMailbox(unread.id)
        #expect(try await first(database.threads(inSmartMailbox: unread.id)) == [])
    }
}
