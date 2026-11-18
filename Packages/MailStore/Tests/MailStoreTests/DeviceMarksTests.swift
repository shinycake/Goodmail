import Foundation
import MailCore
import Testing

@testable import MailStore

/// What only this device knows, as it is read for the Apple Watch.
struct DeviceMarksTests {
    private let database: MailDatabase
    private let outlook = Account(
        id: AccountID(rawValue: "o1"), email: "me@outlook.com", color: .blue, service: .outlook)
    private let gmail = Account(id: AccountID(rawValue: "g1"), email: "me@gmail.com", color: .teal, service: .gmail)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        database = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "DeviceMarksTests-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
        try database.save(outlook)
        try database.save(gmail)
        try database.upsert([thread("pinned", outlook), thread("asleep", gmail), thread("muted", outlook)])
    }

    private func thread(_ id: String, _ account: Account) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: Self.now, isUnread: false, messageCount: 1,
            labelIDs: ["INBOX"])
    }

    @Test func nothingMarkedReadsEmpty() throws {
        #expect(try database.deviceMarks() == DeviceMarks())
    }

    @Test func theMarksAreThoseInTheTables() async throws {
        let commands = MailCommands(store: database, replay: { _ in }, now: { Self.now })
        let pinned = thread("pinned", outlook).id
        let asleep = thread("asleep", gmail).id
        let muted = thread("muted", outlook).id
        _ = try await commands.pin([pinned], true)
        _ = try await commands.snooze([asleep], until: Self.now.addingTimeInterval(3600))
        _ = try await commands.perform(.mute, on: [muted])
        try database.apply(StoreChanges(accountID: outlook.id, signature: "Sent from my Outlook"))
        try database.apply(.accounts([gmail.id]))

        let marks = try database.deviceMarks()

        #expect(marks.pinned == [pinned])
        #expect(marks.asleep == [asleep])
        #expect(marks.muted == [muted])
        #expect(marks.focus == .accounts([gmail.id]))
        #expect(marks.signatures == [outlook.id: "Sent from my Outlook"])
    }

    @Test func aWokenSnoozeIsNoLongerAsleep() async throws {
        let commands = MailCommands(store: database, replay: { _ in }, now: { Self.now })
        let id = thread("asleep", gmail).id
        _ = try await commands.snooze([id], until: Self.now.addingTimeInterval(3600))
        _ = try await commands.unsnooze([id])

        #expect(try database.deviceMarks().asleep.isEmpty)
    }
}
