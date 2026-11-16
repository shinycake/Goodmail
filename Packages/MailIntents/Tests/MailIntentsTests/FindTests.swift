import Foundation
import MailCore
import Testing

@testable import MailIntents

/// Shortcuts' Find actions turn into conditions over the mail on the device, and every detail of a message is a
/// property they can filter, sort or hand to a model.
struct FindTests {
    private let account = Account(
        id: AccountID(rawValue: "A1"), email: "me@example.com", color: .teal, service: .gmail)

    private func order(_ id: String, total: String, minutesAgo: Double, cc: Int = 0) -> (ThreadSummary, Message) {
        let date = Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60)
        let sender = Contact(name: "Amazon.com", address: "auto-confirm@amazon.com")
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Your order of \(id)",
            snippet: "", sender: sender, date: date, isUnread: true, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
        let message = Message(
            id: Message.ID(accountID: account.id, messageID: "m-\(id)"), threadID: id, from: sender,
            to: [Contact(name: nil, address: "me@example.com")],
            cc: (0..<cc).map { Contact(name: nil, address: "cc\($0)@example.com") }, subject: thread.subject,
            date: date, labelIDs: [SystemLabel.inbox, SystemLabel.unread],
            body: MessageBody(plain: "\(id) $1.00\nOrder Total: \(total)"),
            attachments: [Attachment(id: "1", filename: "invoice.pdf", mimeType: "application/pdf", size: 2048)])
        return (thread, message)
    }

    private func host(_ orders: [(ThreadSummary, Message)]) -> FakeHost {
        var host = FakeHost(accountList: [account])
        host.stored = orders.map(\.0)
        for (thread, message) in orders { host.cached[thread.id] = [message] }
        return host
    }

    @Test func ordersFromAmazonSortedByPrice() async throws {
        let host = host([
            order("Echo", total: "$49.99", minutesAgo: 1), order("Cable", total: "$9.99", minutesAgo: 2),
            order("Desk", total: "$129.00", minutesAgo: 3),
        ])
        let found = try await Catalog(host: host).messages(
            matching: .text(.senderDomain, .equals("amazon.com")),
            sortedBy: [MailSort(.totalAmount, ascending: true)], limit: 2)
        #expect(found.map(\.totalAmount) == [9.99, 49.99])
        #expect(found.map(\.currency) == ["USD", "USD"])
    }

    @Test func aMessageCarriesEveryDetail() throws {
        let (thread, message) = order("Echo", total: "$49.99", minutesAgo: 0, cc: 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let catalog = Catalog(host: host([(thread, message)]), calendar: calendar)
        let entity = try #require(try catalog.messages(["A1/Echo/m-Echo"]).first)
        #expect(entity.senderDomain == "amazon.com")
        #expect(entity.ccCount == 2)
        #expect(entity.recipientCount == 3)
        #expect(entity.isToMe)
        #expect(!entity.isFromMe)
        #expect(entity.amounts == [1, 49.99])
        #expect(entity.largestAmount == 49.99)
        #expect(entity.attachmentNames == ["invoice.pdf"])
        #expect(entity.attachmentSize.value == 2048)
        #expect(entity.labels == ["INBOX"])
        #expect(entity.isInInbox && !entity.isRead)
        // 2027-01-15 08:00 UTC is a Friday.
        #expect(entity.weekday == .friday)
        #expect(entity.hour == 8)
    }

    @Test func conversationsAreFoundByTheirListRow() async throws {
        let host = host([order("Echo", total: "$1", minutesAgo: 1), order("Cable", total: "$1", minutesAgo: 2)])
        let found = try await Catalog(host: host).threads(
            matching: .text(.subject, .contains("cable")), sortedBy: [], limit: nil)
        #expect(found.map(\.title) == ["Your order of Cable"])
        #expect(found.first?.senderDomain == "amazon.com")
    }
}
