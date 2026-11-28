import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// An outgoing message is queued, uploading or failed, never both of the last two, and an asleep snooze always says
/// which device wakes it: rows from before the checks are repaired, and the checks refuse new ones.
struct DeliveryChecksTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "DeliveryChecksTests-\(UUID().uuidString)")
        .appending(path: "mail.sqlite")
    private let account = AccountID(rawValue: "a1")
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func draft(_ subject: String) throws -> (Draft, String) {
        let draft = Draft(accountID: account, subject: subject)
        return (draft, String(decoding: try JSONEncoder().encode(draft), as: UTF8.self))
    }

    /// The rows a build before the checks could hold, written to a database migrated up to it.
    private func writeRowsBeforeTheChecks(_ write: (Database) throws -> Void) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path)
        try MailDatabase.migrator.migrate(pool, upTo: "v36-smart-mailboxes")
        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO account (id, email, color, createdAt) VALUES (?, 'me@example.com', 'teal', ?)",
                arguments: [account.rawValue, Self.now])
            try write(db)
        }
        try pool.close()
    }

    private func insertOutgoing(_ db: Database, _ json: String, id: UUID, failure: String?, upload: String?) throws {
        try db.execute(
            sql: """
                INSERT INTO outgoing (id, accountID, purpose, sendAt, failure, upload, draft)
                VALUES (?, ?, 'send', ?, ?, ?, ?)
                """,
            arguments: [id.uuidString, account.rawValue, Self.now, failure, upload, json])
    }

    @Test func aMessageBothFailedAndUploadingIsKeptAsFailedAndTheQueueGoesOn() throws {
        let (both, bothJSON) = try draft("both")
        let (queued, queuedJSON) = try draft("queued")
        let upload = UUID()
        try writeRowsBeforeTheChecks { db in
            try insertOutgoing(db, bothJSON, id: both.id, failure: "rejected", upload: upload.uuidString)
            try insertOutgoing(db, queuedJSON, id: queued.id, failure: nil, upload: nil)
        }

        let database = try MailDatabase(url: url)
        #expect(try database.dueMessages(for: account, by: Self.now).map(\.id) == [queued.id])
        #expect(try database.uploadingMessages(for: account).isEmpty)
        let failed = try database.read { db in
            try String.fetchOne(db, sql: "SELECT failure FROM outgoing WHERE id = ?", arguments: [both.id.uuidString])
        }
        #expect(failed == "rejected", "the writer sees it failed rather than it going a second time")
    }

    @Test func anAsleepSnoozeWithoutAKeeperIsThisDevicesAndAWokenOneHasNone() throws {
        let asleep = ThreadSummary.ID(accountID: account, threadID: "asleep")
        let woke = ThreadSummary.ID(accountID: account, threadID: "woke")
        let wakeAt = Self.now.addingTimeInterval(3600)
        try writeRowsBeforeTheChecks { db in
            try db.execute(
                sql: "INSERT INTO snooze (accountID, threadID, wakeAt, wokeAt, keeper) VALUES (?, ?, ?, NULL, NULL)",
                arguments: [account.rawValue, asleep.threadID, wakeAt])
            try db.execute(
                sql: """
                    INSERT INTO snooze (accountID, threadID, wakeAt, wokeAt, keeper)
                    VALUES (?, ?, NULL, ?, 'thisDevice')
                    """,
                arguments: [account.rawValue, woke.threadID, Self.now])
        }

        let database = try MailDatabase(url: url)
        let snoozes = try database.snoozes(of: [asleep, woke])
        #expect(snoozes[asleep] == .asleep(until: wakeAt, keeper: .thisDevice), "so this device still alerts")
        #expect(snoozes[woke] == .woke(at: Self.now))
        #expect(try database.nextWakeDate() == wakeAt)
    }

    @Test func theChecksRefuseRowsTheCodeCantRead() throws {
        let database = try MailDatabase(url: url)
        try database.save(Account(id: account, email: "me@example.com", color: .teal, service: .gmail))
        let (both, bothJSON) = try draft("both")
        #expect(throws: DatabaseError.self) {
            try database.writeUnannounced { db in
                try insertOutgoing(db, bothJSON, id: both.id, failure: "rejected", upload: UUID().uuidString)
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.writeUnannounced { db in
                try db.execute(
                    sql: "INSERT INTO snooze (accountID, threadID, wakeAt, keeper) VALUES (?, 't', ?, NULL)",
                    arguments: [account.rawValue, Self.now])
            }
        }
        #expect(throws: DatabaseError.self) {
            try database.writeUnannounced { db in
                try db.execute(
                    sql: "INSERT INTO snooze (accountID, threadID, wokeAt, keeper) VALUES (?, 't', ?, 'thisDevice')",
                    arguments: [account.rawValue, Self.now])
            }
        }
    }

    @Test func aRowThatDoesntReadLeavesTheRestOfTheQueueGoing() throws {
        let database = try MailDatabase(url: url)
        try database.save(Account(id: account, email: "me@example.com", color: .teal, service: .gmail))
        let (queued, _) = try draft("queued")
        let (badUpload, badUploadJSON) = try draft("bad upload")
        let later = Self.now.addingTimeInterval(60)
        try database.enqueue(OutgoingMessage(draft: queued, sendAt: later))
        // Both fall due before it.
        try database.writeUnannounced { db in
            try insertOutgoing(db, #"{"from":"a newer build"}"#, id: UUID(), failure: nil, upload: nil)
            try insertOutgoing(db, badUploadJSON, id: badUpload.id, failure: nil, upload: "not an upload")
        }

        #expect(try database.dueMessages(for: account, by: later).map(\.id) == [queued.id])
        #expect(try database.uploadingMessages(for: account).isEmpty)
        #expect(try database.nextSendDate() == later, "nothing waits for a row the queue leaves out")
    }

    @Test func aChangeToARowThatDoesntReadIsRefusedAndLeavesIt() throws {
        let database = try MailDatabase(url: url)
        try database.save(Account(id: account, email: "me@example.com", color: .teal, service: .gmail))
        let id = UUID()
        try database.writeUnannounced { db in
            try insertOutgoing(db, #"{"from":"a newer build"}"#, id: id, failure: nil, upload: nil)
        }

        #expect(throws: (any Error).self) { try database.requeue(id, as: .scheduledSend, at: Self.now) }
        #expect(throws: (any Error).self) { try database.cancel(id) }
        let purpose = try database.read { db in
            try String.fetchOne(db, sql: "SELECT purpose FROM outgoing WHERE id = ?", arguments: [id.uuidString])
        }
        #expect(purpose == "send", "neither change was written")
    }
}
