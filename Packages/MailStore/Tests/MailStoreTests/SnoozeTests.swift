import Foundation
import MailCore
import Testing

@testable import MailStore

/// A snoozed thread leaves the Inbox until its time, then comes back unread; undo puts it back at once.
struct SnoozeTests {
    private let database: MailDatabase
    private let account = Account(id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal)
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SnoozeTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
        try database.upsert([thread("t1"), thread("t2")])
    }

    private func id(_ threadID: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account.id, threadID: threadID)
    }

    private func thread(_ threadID: String) -> ThreadSummary {
        ThreadSummary(
            id: id(threadID), subject: "Subject \(threadID)", snippet: "",
            sender: Contact(name: nil, address: "a@example.com"), date: Self.start.addingTimeInterval(-3600),
            isUnread: false, messageCount: 1, labelIDs: ["INBOX"])
    }

    private func commands(at date: Date) -> MailCommands {
        MailCommands(store: database, replay: { _ in }, now: { date })
    }

    private func inbox() async throws -> [String] {
        var threads = database.threads(in: .inbox).makeAsyncIterator()
        return try await threads.next()?.map(\.id.threadID) ?? []
    }

    @Test func aSnoozedThreadLeavesTheInboxUntilItsTime() async throws {
        let wake = Self.start.addingTimeInterval(3 * 3600)
        try commands(at: Self.start).snooze([id("t1")], until: wake)

        #expect(try await inbox() == ["t2"])
        var snoozed = database.snoozedThreads().makeAsyncIterator()
        #expect(try await snoozed.next()?.map(\.wakeAt) == [wake])
        var directory = database.mailboxDirectory().makeAsyncIterator()
        #expect(try await directory.next()?.snoozedCount == 1)
        #expect(try database.nextWakeDate() == wake)

        #expect(try commands(at: wake.addingTimeInterval(-1)).wakeSnoozed().isEmpty)
        #expect(try commands(at: wake).wakeSnoozed() == [id("t1")])
        #expect(Set(try await inbox()) == ["t1", "t2"])
        #expect(try database.thread(id("t1"))?.isUnread == true, "it comes back unread")
        #expect(try database.snoozes(of: [id("t1")]) == [id("t1"): .woke(at: wake)])
        #expect(try database.nextWakeDate() == nil)
    }

    @Test func undoPutsTheThreadBackAndForgetsTheSnooze() async throws {
        let commands = commands(at: Self.start)
        let undo = try commands.snooze([id("t1")], until: Self.start.addingTimeInterval(3600))
        try commands.undo(undo)
        #expect(Set(try await inbox()) == ["t1", "t2"])
        #expect(try database.snoozes(of: [id("t1")]).isEmpty)
    }

    @Test func movingASnoozedThreadToTheInboxEndsTheSnooze() throws {
        let commands = commands(at: Self.start)
        try commands.snooze([id("t1")], until: Self.start.addingTimeInterval(3600))
        try commands.perform(.moveToInbox, on: [id("t1")])
        #expect(try commands.wakeSnoozed().isEmpty)
        #expect(try database.snoozes(of: [id("t1")]).isEmpty)
    }

    @Test func aWokenThreadIsForgottenAfterADay() throws {
        try commands(at: Self.start).snooze([id("t1")], until: Self.start)
        try commands(at: Self.start).wakeSnoozed()
        try commands(at: Self.start.addingTimeInterval(MailDatabase.wokeShownFor + 1)).wakeSnoozed()
        #expect(try database.snoozes(of: [id("t1")]).isEmpty)
    }

    @Test func removingTheAccountTakesItsSnoozes() throws {
        try commands(at: Self.start).snooze([id("t1")], until: Self.start.addingTimeInterval(3600))
        try database.removeAccount(account.id)
        #expect(try database.nextWakeDate() == nil)
    }
}
