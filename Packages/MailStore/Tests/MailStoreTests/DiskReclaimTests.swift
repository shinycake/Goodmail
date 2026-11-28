import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// Giving storage back once mail leaves the database (ADR-044), on real files. A class, so each test's files go
/// with it.
final class DiskReclaimTests {
    /// More free room on the volume than any of these files needs.
    private static let roomy: Int64 = 1 << 40
    private let folder = Fixture.newFolder()

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private var url: URL { folder.appending(path: "mail.sqlite") }

    @Test func aNewDatabaseGivesPagesBackOnRequest() throws {
        let database = try MailDatabase(url: url)
        #expect(try database.diskUsage().mode == .incremental)
        #expect(try database.read { try Int.fetchOne($0, sql: "PRAGMA auto_vacuum") } == 2)
    }

    @Test func everyConnectionKeepsTheLogSmall() throws {
        let database = try MailDatabase(url: url)
        let limit = Int(DiskReclaim.journalSizeLimit)
        #expect(try database.write { try Int.fetchOne($0, sql: "PRAGMA journal_size_limit") } == limit)
        #expect(try database.read { try Int.fetchOne($0, sql: "PRAGMA journal_size_limit") } == limit)
    }

    @Test func aFileFromBeforeIsRewrittenWhenTheReaderAsksAndShrinks() throws {
        try Fixture.makeLegacyFile(at: url)
        let database = try MailDatabase(url: url)
        try Fixture.fill(database)
        try database.trimCache(to: 0)
        let before = try database.diskUsage()
        #expect(before.mode == .off)
        #expect(before.freeBytes > 0)

        let outcome = try database.reclaimDisk(.readerAsked, volumeFree: Self.roomy, mayConvert: true)

        let after = try database.diskUsage()
        #expect(outcome == .reclaimed(bytes: before.totalBytes - after.totalBytes))
        #expect(after.mode == .incremental)
        #expect(after.fileBytes < before.fileBytes / 2)
        #expect(after.freeBytes == 0)
        #expect(after.pendingBytes == 0)
    }

    @Test func aTrimThenAReleaseShrinksTheFile() throws {
        let database = try MailDatabase(url: url)
        try Fixture.fill(database)
        let full = try database.diskUsage()
        try database.trimCache(to: 0)
        let trimmed = try database.diskUsage()
        #expect(trimmed.freeBytes >= DiskReclaim.afterTrimThresholdBytes)

        let outcome = try database.reclaimDisk(.afterTrim, volumeFree: Self.roomy, mayConvert: false)

        let after = try database.diskUsage()
        #expect(outcome == .reclaimed(bytes: trimmed.totalBytes - after.totalBytes))
        #expect(after.fileBytes < full.fileBytes / 2)
        #expect(after.freeBytes == 0)
        #expect(after.pendingBytes == 0)
    }

    /// A big write while another process reads grows the log far past its limit; a reclaim cuts it at once.
    @Test func aLogPastItsLimitIsCutAtOnce() throws {
        let database = try MailDatabase(url: url)
        let otherProcess = try MailDatabase(url: url)
        try withExtendedLifetime(try otherProcess.makeSnapshot()) {
            try Fixture.fill(database)
        }
        let grown = try database.diskUsage()
        try #require(grown.walBytes > DiskReclaim.journalSizeLimit)

        let outcome = try database.reclaimDisk(.readerAsked, volumeFree: Self.roomy, mayConvert: false)

        let after = try database.diskUsage()
        #expect(outcome == .reclaimed(bytes: grown.totalBytes - after.totalBytes))
        #expect(after.pendingBytes == 0)
    }

    /// A rewrite copies all the mail through the log; the files on disk are the mail's size right after, with no
    /// write in between.
    @Test func aRewriteLeavesNoLogBehind() throws {
        try Fixture.makeLegacyFile(at: url)
        let database = try MailDatabase(url: url)
        try Fixture.fill(database)
        let before = try database.diskUsage()
        try #require(before.liveBytes > DiskReclaim.journalSizeLimit)

        let outcome = try database.reclaimDisk(.readerAsked, volumeFree: Self.roomy, mayConvert: true)

        let after = try database.diskUsage()
        #expect(outcome == .reclaimed(bytes: before.totalBytes - after.totalBytes))
        #expect(after.mode == .incremental)
        #expect(after.pendingBytes == 0)
        #expect(after.walBytes <= DiskReclaim.journalSizeLimit)
    }

    @Test func nothingToGiveBackDoesNothing() throws {
        let database = try MailDatabase(url: url)
        #expect(try database.reclaimDisk(.afterTrim, volumeFree: Self.roomy, mayConvert: true) == .nothing)
    }

    /// The Notification Service Extension reading as the app reclaims: the pages go back, but the files shrink only
    /// at a reclaim after its read.
    @Test(.timeLimit(.minutes(1))) func aReadInAnotherProcessLeavesTheShrinkForTheNextReclaim() throws {
        let database = try MailDatabase(url: url)
        let otherProcess = try MailDatabase(url: url)
        try Fixture.fill(database)
        try database.trimCache(to: 0)
        let trimmed = try database.diskUsage()

        do {
            let reading = try otherProcess.makeSnapshot()
            let released = try database.reclaimDisk(.readerAsked, volumeFree: Self.roomy, mayConvert: false)
            let unshrunk = try database.diskUsage()
            let again = try database.reclaimDisk(.readerAsked, volumeFree: Self.roomy, mayConvert: false)
            withExtendedLifetime(reading) {}
            #expect(released == .partly(bytes: trimmed.totalBytes - unshrunk.totalBytes))
            #expect(unshrunk.fileBytes == trimmed.fileBytes)
            #expect(unshrunk.freeBytes == 0)
            #expect(again == .notNow)
        }
        // The short wait for readers was only for emptying the log; writes wait as long as before.
        #expect(try database.write { try Int.fetchOne($0, sql: "PRAGMA busy_timeout") } == 5000)

        let waiting = try database.diskUsage()
        #expect(waiting.pendingBytes >= DiskReclaim.afterTrimThresholdBytes)
        let outcome = try database.reclaimDisk(.afterTrim, volumeFree: Self.roomy, mayConvert: false)

        let after = try database.diskUsage()
        #expect(outcome == .reclaimed(bytes: waiting.totalBytes - after.totalBytes))
        #expect(after.fileBytes < trimmed.fileBytes / 2)
        #expect(after.pendingBytes == 0)
    }

    #if os(macOS) || os(Linux)
        /// `suspendAll()` suspends every database in the process, so these run in processes of their own, where it
        /// can't fail other tests' writes.
        @Test func aSuspendedDatabaseGivesNoPagesBack() async {
            await #expect(processExitsWith: .success) {
                let folder = Fixture.newFolder()
                defer { try? FileManager.default.removeItem(at: folder) }
                let database = try MailDatabase(url: folder.appending(path: "mail.sqlite"))
                try Fixture.fill(database)
                try database.trimCache(to: 0)
                MailDatabase.suspendAll()
                let outcome = try database.reclaimDisk(.readerAsked, volumeFree: 1 << 40, mayConvert: true)
                guard outcome == .notNow, try database.diskUsage().freeBytes > 0 else { exit(EXIT_FAILURE) }
            }
        }

        @Test func aSuspendedDatabaseDoesNotEmptyTheLog() async {
            await #expect(processExitsWith: .success) {
                let folder = Fixture.newFolder()
                defer { try? FileManager.default.removeItem(at: folder) }
                let url = folder.appending(path: "mail.sqlite")
                let database = try MailDatabase(url: url)
                let otherProcess = try MailDatabase(url: url)
                try Fixture.fill(database)
                try database.trimCache(to: 0)
                // The read ends with this statement, so only the suspension can stop the next reclaim.
                let released = try withExtendedLifetime(try otherProcess.makeSnapshot()) {
                    try database.reclaimDisk(.readerAsked, volumeFree: 1 << 40, mayConvert: true)
                }
                let pending = try database.diskUsage()
                guard case .partly = released, pending.pendingBytes > 0 else { exit(EXIT_FAILURE) }

                MailDatabase.suspendAll()
                let outcome = try database.reclaimDisk(.readerAsked, volumeFree: 1 << 40, mayConvert: true)
                guard outcome == .notNow, try database.diskUsage().fileBytes == pending.fileBytes else {
                    exit(EXIT_FAILURE)
                }
            }
        }
    #endif

    @Test(.timeLimit(.minutes(1))) func observationsStillDeliverAfterARewrite() async throws {
        try Fixture.makeLegacyFile(at: url)
        let database = try MailDatabase(url: url)
        try Fixture.fill(database, threads: 10)
        var inbox = database.threads(in: .inbox, window: .whole).makeAsyncIterator()
        #expect(try await inbox.next()?.threads.count == 10)

        try database.trimCache(to: 0)
        guard case .reclaimed = try database.reclaimDisk(.readerAsked, volumeFree: Self.roomy, mayConvert: true) else {
            Issue.record("The file wasn't rewritten.")
            return
        }
        try database.upsert([Fixture.thread(10)])

        #expect(try await inbox.next()?.threads.count == 11)
    }
}

/// Databases for `DiskReclaimTests`. Static, so the suspension tests' own processes can use them too.
private enum Fixture {
    static let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func newFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "DiskReclaimTests-\(UUID().uuidString)")
    }

    /// A file migrated as every file was before ADR-044, with no `auto_vacuum`.
    static func makeLegacyFile(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pool = try DatabasePool(path: url.path)
        try MailDatabase.migrator.migrate(pool)
        try pool.close()
    }

    static func thread(_ index: Int) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t\(index)"), subject: "Subject \(index)",
            snippet: "", sender: Contact(name: nil, address: "a@example.com"),
            date: now.addingTimeInterval(Double(index)), isUnread: false, messageCount: 1, labelIDs: ["INBOX"])
    }

    /// Stores `threads` threads, each with a 40 KB body the cache cap can evict.
    static func fill(_ database: MailDatabase, threads: Int = 150) throws {
        try database.save(account)
        let summaries = (0..<threads).map(thread)
        try database.upsert(summaries)
        for summary in summaries {
            let message = Message(
                id: Message.ID(accountID: account.id, messageID: "m-\(summary.id.threadID)"),
                threadID: summary.id.threadID, from: summary.sender, subject: summary.subject, date: summary.date,
                body: MessageBody(html: nil, plain: String(repeating: "word ", count: 8_000)))
            try database.save([message], inThread: summary.id, fetchedAt: now, accessedAt: now)
        }
    }
}
