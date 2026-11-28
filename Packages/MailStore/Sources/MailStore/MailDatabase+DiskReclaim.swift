import Foundation
import GRDB

#if canImport(os)
    import os
#endif

/// Giving the reader's storage back once mail leaves the database (ADR-044). SQLite keeps the pages deleted rows
/// leave free inside the file for later rows, so removing downloaded mail changed nothing iOS Settings shows.
extension MailDatabase {
    /// Free pages are given back this many at a time, each its own short write, so the other process can write in
    /// between and a suspension stops the reclaim at the next one.
    static let releaseChunkPages: Int64 = 1024
    /// How long emptying the log waits for other connections' reads to end, in milliseconds. Emptying it holds off
    /// every writer, the other process's too, so it waits far less than a write's usual timeout.
    static let emptyLogWaitMilliseconds = 250

    /// Runs on every connection the pool opens.
    static func prepare(_ db: Database) throws {
        try db.execute(sql: "PRAGMA journal_size_limit = \(DiskReclaim.journalSizeLimit)")
    }

    /// Makes a file that holds no tables yet give its free pages back on request. SQLite settles the mode when the
    /// first table is created, but opening the pool already wrote the file's header, so it takes a `VACUUM`. Two
    /// processes opening a new file together may both do it, which is harmless.
    static func startIncrementalIfNew(_ pool: DatabasePool) throws {
        try pool.writeWithoutTransaction { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master") == 0 else { return }
            try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
            try db.execute(sql: "VACUUM")
        }
    }

    /// What the database takes on disk now.
    public func diskUsage() throws -> DiskUsage {
        let (pages, freePages, pageSize, autoVacuum) = try read { db in
            (
                try Int64.fetchOne(db, sql: "PRAGMA page_count") ?? 0,
                try Int64.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0,
                try Int64.fetchOne(db, sql: "PRAGMA page_size") ?? 0,
                try Int.fetchOne(db, sql: "PRAGMA auto_vacuum") ?? 0
            )
        }
        return DiskUsage(
            fileBytes: try Self.fileSize(atPath: path),
            walBytes: try Self.fileSize(atPath: path + "-wal"),
            freeBytes: freePages * pageSize,
            liveBytes: (pages - freePages) * pageSize,
            pageSize: pageSize,
            mode: DiskUsage.Mode(autoVacuum: autoVacuum)
        )
    }

    /// Gives back what `DiskReclaim.plan` says for `reason`. `volumeFree` is the space left on the database's volume,
    /// and `mayConvert` whether a file made before ADR-044 may be rewritten now.
    ///
    /// Another process holding the database, or this one being suspended or interrupted, isn't an error: the reclaim
    /// stops, says how far it got (`.partly` or `.notNow`), and the next one picks up from there. It changes no mail,
    /// so observers aren't told.
    public func reclaimDisk(
        _ reason: DiskReclaim.Reason, volumeFree: Int64, mayConvert: Bool
    ) throws -> DiskReclaim.Outcome {
        let before = try diskUsage()
        let plan = DiskReclaim.plan(for: before, asked: reason, volumeFree: volumeFree, mayConvert: mayConvert)
        guard plan != .nothing else { return .nothing }
        let walPath = path + "-wal"
        let stopped = try Self.notNow {
            try writeWithoutTransaction { db in try Self.carryOut(plan, in: db, walPath: walPath) }
        }
        let after = try diskUsage()
        let bytes = max(0, before.totalBytes - after.totalBytes)
        guard let stopped else { return .reclaimed(bytes: bytes) }

        #if canImport(os)
            Logger(subsystem: "com.idanbirman.goodmail", category: "storage")
                .info("Storage wasn't all given back this time: \(stopped, privacy: .public)")
        #endif
        // Pages given back are no longer free, and a rewrite changes the mode, whether or not the log was emptied.
        let changedFile = after.freeBytes < before.freeBytes || after.mode != before.mode
        return changedFile ? .partly(bytes: bytes) : .notNow
    }

    private static func carryOut(_ plan: DiskReclaim, in db: Database, walPath: String) throws {
        switch plan {
        case .nothing:
            return
        case .emptyLog:
            break
        case .release(let pages):
            var left = pages
            while left > 0 {
                let chunk = min(left, releaseChunkPages)
                try db.execute(sql: "PRAGMA incremental_vacuum(\(chunk))")
                left -= chunk
            }
        case .convert:
            try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
            try db.execute(sql: "VACUUM")
        }
        try emptyLog(db, checkpoint: DiskReclaim.Checkpoint(walBytes: try fileSize(atPath: walPath)))
    }

    /// Copies the log into the file, which cuts the file down to its last page, and starts the log again, as
    /// `checkpoint` says. It waits only `emptyLogWaitMilliseconds` for other connections' reads to end, then puts the
    /// connection's usual wait back. Run as SQL rather than through `Database.checkpoint`, so a suspended database
    /// refuses it like any other write.
    private static func emptyLog(_ db: Database, checkpoint mode: DiskReclaim.Checkpoint) throws {
        let usualWait = try Int.fetchOne(db, sql: "PRAGMA busy_timeout") ?? 0
        try db.execute(sql: "PRAGMA busy_timeout = \(emptyLogWaitMilliseconds)")
        let checkpoint = Result { try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(\(mode.rawValue))") }
        try db.execute(sql: "PRAGMA busy_timeout = \(usualWait)")
        // The first column says whether a read in another connection stopped it before it was done.
        let blocked: Int = try checkpoint.get()?[0] ?? 0
        guard blocked == 0 else {
            throw DatabaseError(resultCode: .SQLITE_BUSY, message: "A read kept the write-ahead log from emptying.")
        }
    }

    /// Runs `work`, and returns rather than throws an error that means the reclaim must stop for now: another
    /// connection holds a lock it needs (`SQLITE_BUSY`), or `suspendAll()` interrupted it or refused its lock
    /// (`SQLITE_INTERRUPT`, `SQLITE_ABORT`).
    private static func notNow(_ work: () throws -> Void) throws -> DatabaseError? {
        do {
            try work()
            return nil
        } catch let error as DatabaseError
            where [.SQLITE_BUSY, .SQLITE_INTERRUPT, .SQLITE_ABORT].contains(error.resultCode)
        {
            return error
        }
    }

    /// The size of the file at `path`, or 0 when there is none.
    private static func fileSize(atPath path: String) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        return Int64(try URL(filePath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
}
