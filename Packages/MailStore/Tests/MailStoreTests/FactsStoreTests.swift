import Foundation
import MailCore
import Testing

@testable import MailStore

/// Shortcuts' Find actions and rules read mail as facts: cached messages with their thread, pins, snoozes and the
/// names of their labels.
struct FactsStoreTests {
    private let database: MailDatabase
    private let account = AccountID(rawValue: "a1")
    private let names = [SystemLabel.inbox: "Inbox"]
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "FactsStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(Account(id: account, email: "me@example.com", color: .teal, service: .gmail))
    }

    private func store(_ id: String, minutesAgo: Double, body: String, labels: Set<String> = ["INBOX"]) throws {
        let date = now.addingTimeInterval(-minutesAgo * 60)
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account, threadID: id), subject: "Order \(id)", snippet: "",
            sender: Contact(name: "Shop", address: "orders@shop.com"), date: date, isUnread: true, messageCount: 1,
            labelIDs: labels)
        try database.apply(
            StoreChanges(
                accountID: account, upserts: [thread],
                labels: [MailLabel(id: "Label_1", name: "Receipts", kind: .user)]))
        let message = Message(
            id: Message.ID(accountID: account, messageID: "m-\(id)"), threadID: id,
            from: thread.sender, to: [Contact(name: nil, address: "me@example.com")], subject: thread.subject,
            date: date, labelIDs: labels, body: MessageBody(plain: body))
        try database.save([message], inThread: thread.id)
    }

    @Test func matchingMessagesComeNewestFirstWithTheirAmounts() throws {
        try store("old", minutesAgo: 60 * 24 * 10, body: "Order total: $5.00")
        try store("cable", minutesAgo: 60, body: "Order total: $9.99")
        try store("echo", minutesAgo: 30, body: "Order total: $49.99")
        try store("note", minutesAgo: 10, body: "See you soon")
        let lastWeek = MailCondition.all([
            .date(.date, .withinLast(seconds: 7 * 86400)), .text(.senderDomain, .equals("shop.com")),
            .number(.totalAmount, .greaterThan(0)),
        ])
        let found = try database.messageFacts(
            matching: lastWeek, in: MailCondition.Context(now: now), mailboxNames: names)
        #expect(found.map(\.envelope.thread.threadID) == ["echo", "cable"])
        let byPrice = MailSort.sorted(found, by: [MailSort(.totalAmount, ascending: true)])
        #expect(byPrice.map(\.envelope.thread.threadID) == ["cable", "echo"])
    }

    @Test func factsCarryPinsSnoozesAndLabelNames() throws {
        try store("t", minutesAgo: 1, body: "Hi", labels: ["INBOX", "Label_1"])
        let id = ThreadSummary.ID(accountID: account, threadID: "t")
        try database.setPins([id: true])
        try database.setSnoozes([id: .asleep(until: now.addingTimeInterval(3600), keeper: .thisDevice)])
        let facts = try #require(try database.messageFacts(inThreads: [id], mailboxNames: names).first)
        #expect(facts.local.isPinned)
        #expect(facts.date(.snoozedUntil) == now.addingTimeInterval(3600))
        #expect(facts.texts(.mailbox) == ["Inbox", "Receipts"])
        #expect(facts.content?.bodyText == "Hi")
    }

    @Test func threadFactsKnowOnlyTheirListRow() throws {
        try store("t", minutesAgo: 1, body: "Order total: $9.99")
        let byBody = MailCondition.text(.body, .contains("total"))
        #expect(try database.threadFacts(matching: byBody, in: .init(now: now), mailboxNames: names).isEmpty)
        let bySubject = MailCondition.text(.subject, .contains("order"))
        let found = try database.threadFacts(matching: bySubject, in: .init(now: now), mailboxNames: names)
        #expect(found.map(\.envelope.thread.threadID) == ["t"])
    }
}

extension FactsStoreTests {
    @Test func threadFactsByIDAreNewestFirstWithTheirPins() throws {
        try store("old", minutesAgo: 10, body: "")
        try store("new", minutesAgo: 1, body: "")
        let ids = ["old", "gone", "new"].map { ThreadSummary.ID(accountID: account, threadID: $0) }
        try database.setPins([ids[0]: true])
        let found = try database.threadFacts(ids, mailboxNames: names)
        #expect(found.map(\.envelope.thread.threadID) == ["new", "old"])
        #expect(found.map(\.local.isPinned) == [false, true])
    }
}
