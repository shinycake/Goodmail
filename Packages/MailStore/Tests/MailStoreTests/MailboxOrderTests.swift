import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// A label's mailbox orders by the copy of the thread's date on each label row, so the copy has to follow the
/// thread however it changes, and a database from before the copy gets one.
struct MailboxOrderTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "MailboxOrderTests-\(UUID().uuidString)")
        .appending(path: "mail.sqlite")
    private let account = AccountID(rawValue: "a1")
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func thread(_ id: String, minutesAgo: Double, labels: Set<String> = [SystemLabel.inbox]) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account, threadID: id), subject: "Subject \(id)", snippet: "",
            sender: Contact(name: nil, address: "\(id)@example.com"), date: Self.now - minutesAgo * 60,
            isUnread: false, messageCount: 1, labelIDs: labels)
    }

    private func openWithThreads(_ threads: [ThreadSummary]) throws -> MailDatabase {
        let database = try MailDatabase(url: url)
        try database.save(Account(id: account, email: "me@example.com", color: .teal, service: .gmail))
        try database.upsert(threads)
        return database
    }

    private func listed(_ mailbox: Mailbox, in database: MailDatabase) throws -> [String] {
        try database.threads(in: mailbox, limit: 50).map(\.id.threadID)
    }

    /// Label rows whose date isn't their thread's.
    private func staleCopies(in database: MailDatabase) throws -> Int {
        try database.pool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM threadLabel
                    JOIN thread ON thread.accountID = threadLabel.accountID AND thread.id = threadLabel.threadID
                    WHERE threadLabel.date IS NOT thread.date
                    """) ?? 0
        }
    }

    @Test func aThreadRedatedBySyncMovesInItsLabels() throws {
        let database = try openWithThreads([thread("old", minutesAgo: 60), thread("new", minutesAgo: 1)])

        try database.upsert([thread("old", minutesAgo: 0)])

        #expect(try listed(.inbox, in: database) == ["old", "new"])
        #expect(try staleCopies(in: database) == 0)
    }

    @Test func aThreadRedatedWithoutItsLabelsMovesInThemToo() throws {
        let database = try openWithThreads([thread("old", minutesAgo: 60), thread("new", minutesAgo: 1)])

        try database.pool.write { db in
            try db.execute(sql: "UPDATE thread SET date = ? WHERE id = 'old'", arguments: [Self.now])
        }

        #expect(try listed(.inbox, in: database) == ["old", "new"])
        #expect(try staleCopies(in: database) == 0)
    }

    enum Rewrite: CaseIterable, Sendable {
        case markedReadFromTheOutbox, syncedUnchanged, syncedWithAnotherLabel
    }

    /// IMAP dates are to the second, so threads on the same date are common; rewriting one mustn't move it.
    @Test(arguments: Rewrite.allCases)
    func aThreadRewrittenKeepsItsPlaceAmongThreadsOfTheSameDate(_ rewrite: Rewrite) throws {
        var earlier = thread("earlier", minutesAgo: 5)
        earlier.isUnread = true
        let database = try openWithThreads([earlier, thread("later", minutesAgo: 5)])
        #expect(try listed(.inbox, in: database) == ["later", "earlier"])

        switch rewrite {
        case .markedReadFromTheOutbox:
            _ = try database.enqueue(
                [OutboxIntent(threadID: "earlier", action: .markRead(true), createdAt: Self.now)], account: account)
        case .syncedUnchanged:
            try database.upsert([earlier])
        case .syncedWithAnotherLabel:
            earlier.labelIDs.insert(SystemLabel.starred)
            try database.upsert([earlier])
        }

        #expect(try listed(.inbox, in: database) == ["later", "earlier"])
    }

    @Test func aLabelAddedFromTheOutboxCarriesItsThreadsDate() throws {
        let database = try openWithThreads([
            thread("old", minutesAgo: 60),
            thread("new", minutesAgo: 1, labels: [SystemLabel.inbox, SystemLabel.starred]),
        ])

        _ = try database.enqueue(
            [OutboxIntent(threadID: "old", action: .star(true), createdAt: Self.now)], account: account)

        #expect(try listed(.starred, in: database) == ["new", "old"])
        #expect(try staleCopies(in: database) == 0)
    }

    @Test func aDatabaseFromBeforeTheCopyGetsOne() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path)
        try MailDatabase.migrator.migrate(pool, upTo: "v38-watch-changes")
        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO account (id, email, color, createdAt) VALUES (?, 'me@example.com', 'teal', ?)",
                arguments: [account.rawValue, Self.now])
            for (id, minutesAgo) in [("old", 60.0), ("new", 1.0)] {
                try db.execute(
                    sql: """
                        INSERT INTO thread (accountID, id, subject, snippet, senderAddress, date, isUnread, messageCount)
                        VALUES (?, ?, '', '', 'sender@example.com', ?, 0, 1)
                        """,
                    arguments: [account.rawValue, id, Self.now - minutesAgo * 60])
                for label in [SystemLabel.inbox, "Label_1"] {
                    try db.execute(
                        sql: "INSERT INTO threadLabel (accountID, threadID, labelID) VALUES (?, ?, ?)",
                        arguments: [account.rawValue, id, label])
                }
            }
        }
        try pool.close()

        let database = try MailDatabase(url: url)

        #expect(try staleCopies(in: database) == 0)
        #expect(try database.pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM threadLabel") } == 4)
        #expect(try listed(Mailbox(labelID: "Label_1"), in: database) == ["new", "old"])
        #expect(
            try database.thread(ThreadSummary.ID(accountID: account, threadID: "old"))?.labelIDs
                == [SystemLabel.inbox, "Label_1"])
    }
}
