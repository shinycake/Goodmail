/// What the database file takes on disk, and how much of it is mail (ADR-044).
public struct DiskUsage: Sendable, Equatable {
    /// How SQLite gives back the pages that deleted rows leave free (`PRAGMA auto_vacuum`).
    public enum Mode: Sendable, Equatable {
        /// Free pages stay in the file for later rows; only a whole `VACUUM` gives them back. Every file made before
        /// ADR-044.
        case off
        /// Every commit gives its free pages back.
        case full
        /// Free pages stay until `PRAGMA incremental_vacuum` gives them back. Every file made since ADR-044.
        case incremental

        /// The mode `PRAGMA auto_vacuum` reports as `value`.
        init(autoVacuum value: Int) {
            switch value {
            case 1: self = .full
            case 2: self = .incremental
            default: self = .off
            }
        }
    }

    /// The database file's size.
    public var fileBytes: Int64
    /// The write-ahead log's size, which counts on disk as much as the file.
    public var walBytes: Int64
    /// The pages that hold nothing.
    public var freeBytes: Int64
    /// The pages that hold the mail.
    public var liveBytes: Int64
    public var pageSize: Int64
    public var mode: Mode

    /// Everything the database takes on disk.
    public var totalBytes: Int64 { fileBytes + walBytes }

    /// What the disk keeps that the database no longer needs, and emptying the log gives back: the file's tail past
    /// its last page, which pages given back in the log still occupy, and the log past the size it keeps.
    public var pendingBytes: Int64 {
        max(0, fileBytes - liveBytes - freeBytes) + max(0, walBytes - DiskReclaim.journalSizeLimit)
    }
}

/// How to give the reader's storage back from the database file: a pure decision over its `DiskUsage`, which
/// `MailDatabase.reclaimDisk(_:volumeFree:mayConvert:)` carries out. Every step but `.nothing` ends by emptying the
/// write-ahead log, which is what shrinks the files on disk.
public enum DiskReclaim: Sendable, Equatable {
    /// Nothing worth giving back, or nothing that may be done now.
    case nothing
    /// Only empty the log: an earlier reclaim gave the pages back, but a read in another process kept the files from
    /// shrinking then.
    case emptyLog
    /// Hand `pages` free pages back (`PRAGMA incremental_vacuum`).
    case release(pages: Int64)
    /// Rewrite a file made before ADR-044 so it can give pages back from now on (`VACUUM`), which gives back every
    /// free page it holds on the way.
    case convert

    /// Why a reclaim runs.
    public enum Reason: Sendable, Equatable {
        /// The cache cap just evicted mail at the end of a sync.
        case afterTrim
        /// The reader asked for the downloaded mail to be removed.
        case readerAsked
    }

    /// What a reclaim did.
    public enum Outcome: Sendable, Equatable {
        /// The database takes `bytes` less on disk.
        case reclaimed(bytes: Int64)
        /// The pages were given back, but a read in another process kept the files from shrinking: the database
        /// takes `bytes` less so far, and the next reclaim empties the log.
        case partly(bytes: Int64)
        /// The plan was `.nothing`.
        case nothing
        /// Another process held the database, or this one was suspended or interrupted, before anything changed.
        /// The next reclaim finds the same pages.
        case notNow
    }

    /// How emptying the log starts it again (`PRAGMA wal_checkpoint`).
    enum Checkpoint: String, Sendable, Equatable {
        /// The next write starts the log from the top and cuts it to `journalSizeLimit`. The usual way: an empty log
        /// makes every process that opens the database write one back (GRDB's `setUpWALMode`), and the extensions
        /// open it often.
        case restart = "RESTART"
        /// Cut the log to nothing now. Only for a log past `journalSizeLimit`, as a rewrite leaves it, which would
        /// otherwise stay as big as the mail until the next write.
        case truncate = "TRUNCATE"

        init(walBytes: Int64) {
            self = walBytes > DiskReclaim.journalSizeLimit ? .truncate : .restart
        }
    }

    /// The most the write-ahead log keeps on disk once it starts again from the top (`PRAGMA journal_size_limit`).
    public static let journalSizeLimit: Int64 = 8 << 20
    /// After a trim, nothing is done for less than this, so a sync that evicts a few bodies doesn't write.
    static let afterTrimThresholdBytes: Int64 = 4 << 20
    /// After a trim, a file made before ADR-044 is rewritten only while the mail in it is this small, so the rewrite
    /// is quick.
    static let convertAfterTrimLiveBytes: Int64 = 64 << 20
    /// The most mail a rewrite the reader asked for takes on. It holds off every writer while it runs, the
    /// Notification Service Extension too, whose writes give up after five seconds.
    static let convertWhenAskedLiveBytes: Int64 = 256 << 20
    /// A rewrite writes the mail to a temporary copy and that copy into the log before the old pages go, so it needs
    /// room for the files this many times over.
    static let convertRoomFactor: Int64 = 2

    /// What to do for `reason` with the database at `usage` and `volumeFree` bytes free on its volume. A rewrite holds
    /// the database for a while, so it happens only when `mayConvert` (the reader is looking, or on the Mac).
    public static func plan(
        for usage: DiskUsage, asked reason: Reason, volumeFree: Int64, mayConvert: Bool
    ) -> DiskReclaim {
        let threshold = reason == .afterTrim ? afterTrimThresholdBytes : 1
        let convertLimit = reason == .afterTrim ? convertAfterTrimLiveBytes : convertWhenAskedLiveBytes
        let roomToConvert = volumeFree >= usage.totalBytes * convertRoomFactor
        switch usage.mode {
        case .incremental where usage.freeBytes >= threshold:
            return .release(pages: usage.freeBytes / usage.pageSize)
        case .off where mayConvert && roomToConvert && usage.liveBytes < convertLimit:
            return .convert
        case .incremental, .off, .full:
            return usage.pendingBytes >= threshold ? .emptyLog : .nothing
        }
    }
}
