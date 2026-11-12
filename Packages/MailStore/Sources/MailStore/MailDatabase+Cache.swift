import Foundation
import GRDB
import MailCore

/// The offline cache's cap (ADR-007): cached bodies and attachment files share one budget, and the least recently
/// read go first. Thread summaries are never evicted, so lists and search keep working; an evicted body is fetched
/// again when its thread opens.
extension MailDatabase {
    /// The most the cache keeps, in bytes: 1 GB. The one place the cap is set; callers can pass a smaller one.
    public static let cacheLimit = 1 << 30

    public struct CacheUsage: Equatable, Sendable {
        /// The bytes of cached message bodies, with their search text.
        public var bodies: Int
        /// The bytes of attachment files.
        public var attachments: Int
        public var total: Int { bodies + attachments }
    }

    /// What a trim removed.
    public struct CacheTrim: Equatable, Sendable {
        /// Threads whose bodies were dropped.
        public var threads = 0
        /// Attachment files' folders removed, one per attachment.
        public var attachments = 0
        public var freedBytes = 0
    }

    /// Marks the thread's bodies as read at `date`.
    public func touchMessages(inThread thread: ThreadSummary.ID, at date: Date = .now) throws {
        // Not `write`: evicting doesn't care about this and the other process needn't hear of it.
        try pool.write { db in
            try db.execute(
                sql: "UPDATE message SET accessedAt = ? WHERE accountID = ? AND threadID = ?",
                arguments: [date, thread.accountID.rawValue, thread.threadID])
        }
    }

    /// The cache's size now. `attachments` is the folder the attachment files are kept in, if any.
    public func cacheUsage(attachments: URL? = nil) throws -> CacheUsage {
        let bodies = try pool.read { db in try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(size), 0) FROM message") ?? 0
        }
        return CacheUsage(
            bodies: bodies, attachments: Self.attachmentFolders(in: attachments).reduce(0) { $0 + $1.size })
    }

    /// Evicts the least recently read bodies (a thread's together) and attachment files until the cache fits
    /// `limit`. Threads with a draft or a queued action are never evicted, though they count toward the size.
    @discardableResult
    public func trimCache(to limit: Int = MailDatabase.cacheLimit, attachments: URL? = nil) throws -> CacheTrim {
        let (usage, threads) = try pool.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(size), 0) FROM message") ?? 0,
                try Self.evictableThreads(in: db)
            )
        }
        let folders = Self.attachmentFolders(in: attachments)
        var excess = usage + folders.reduce(0) { $0 + $1.size } - limit
        guard excess > 0 else { return CacheTrim() }

        enum Candidate {
            case thread(EvictableThread)
            case attachment(AttachmentFolder)
            var accessedAt: Date {
                switch self {
                case .thread(let thread): thread.accessedAt
                case .attachment(let folder): folder.accessedAt
                }
            }
        }
        let candidates = (threads.map(Candidate.thread) + folders.map(Candidate.attachment))
            .sorted { $0.accessedAt < $1.accessedAt }

        var trim = CacheTrim()
        var evicted: [EvictableThread] = []
        for candidate in candidates where excess > 0 {
            switch candidate {
            case .thread(let thread):
                evicted.append(thread)
                excess -= thread.size
                trim.freedBytes += thread.size
            case .attachment(let folder):
                // A file that can't be removed stays counted: skip it, and the next trim tries again.
                guard (try? FileManager.default.removeItem(at: folder.url)) != nil else { continue }
                excess -= folder.size
                trim.freedBytes += folder.size
                trim.attachments += 1
            }
        }
        trim.threads = evicted.count
        if !evicted.isEmpty {
            try write { db in
                for thread in evicted {
                    try db.execute(
                        sql: "DELETE FROM message WHERE accountID = ? AND threadID = ?",
                        arguments: [thread.accountID, thread.threadID])
                }
            }
        }
        return trim
    }

    private struct EvictableThread {
        var accountID: String
        var threadID: String
        var size: Int
        var accessedAt: Date
    }

    /// The threads with cached bodies that may go, each with the size and last read of all its bodies.
    private static func evictableThreads(in db: Database) throws -> [EvictableThread] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT m.accountID, m.threadID, SUM(m.size) AS size, MAX(COALESCE(m.accessedAt, m.fetchedAt)) AS accessedAt
                FROM message m
                WHERE NOT EXISTS (
                        SELECT 1 FROM outbox o WHERE o.accountID = m.accountID AND o.threadID = m.threadID)
                    AND NOT EXISTS (
                        SELECT 1 FROM threadLabel l
                        WHERE l.accountID = m.accountID AND l.threadID = m.threadID AND l.labelID = ?)
                GROUP BY m.accountID, m.threadID
                """,
            arguments: [SystemLabel.draft]
        ).map { row in
            EvictableThread(
                accountID: row["accountID"], threadID: row["threadID"], size: row["size"], accessedAt: row["accessedAt"]
            )
        }
    }

    private struct AttachmentFolder {
        var url: URL
        var size: Int
        /// The newest modification of its files: the app touches a file each time it is opened.
        var accessedAt: Date
    }

    /// The attachment files under `root`, as `<account>/<message>-<part>/<file>`, one entry per attachment.
    private static func attachmentFolders(in root: URL?) -> [AttachmentFolder] {
        guard let root else { return [] }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let manager = FileManager.default
        func children(of url: URL) -> [URL] {
            (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
        }
        return children(of: root).flatMap { account in
            children(of: account).compactMap { folder in
                let files = children(of: folder).compactMap { try? $0.resourceValues(forKeys: Set(keys)) }
                guard !files.isEmpty else { return nil }
                return AttachmentFolder(
                    url: folder,
                    size: files.reduce(0) { $0 + ($1.fileSize ?? 0) },
                    accessedAt: files.compactMap(\.contentModificationDate).max() ?? .distantPast)
            }
        }
    }
}

extension MailDatabase: PrefetchStore {
    public func threadsWithoutBodies(account: AccountID, among newest: Int) throws -> [ThreadSummary.ID] {
        try pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM (
                        SELECT t.id, t.date FROM thread t
                        WHERE t.accountID = ? AND NOT EXISTS (
                            SELECT 1 FROM threadLabel l
                            WHERE l.accountID = t.accountID AND l.threadID = t.id AND l.labelID IN (?, ?))
                        ORDER BY t.date DESC
                        LIMIT ?
                    ) AS newest
                    WHERE NOT EXISTS (SELECT 1 FROM message m WHERE m.accountID = ? AND m.threadID = newest.id)
                    ORDER BY date DESC
                    """,
                arguments: [account.rawValue, SystemLabel.spam, SystemLabel.trash, newest, account.rawValue]
            ).map { ThreadSummary.ID(accountID: account, threadID: $0) }
        }
    }

    public func savePrefetched(_ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date) throws {
        // Dated by the mail, not the fetch: prefetching shouldn't make bodies look more read than any the reader opened.
        var accessedAt = min(messages.map(\.date).max() ?? fetchedAt, fetchedAt)
        // Unless the reader opened the thread while it was being fetched.
        let read = try pool.read { db in
            try Date.fetchOne(
                db, sql: "SELECT MAX(accessedAt) FROM message WHERE accountID = ? AND threadID = ?",
                arguments: [thread.accountID.rawValue, thread.threadID])
        }
        if let read { accessedAt = max(accessedAt, read) }
        try save(messages, inThread: thread, fetchedAt: fetchedAt, accessedAt: accessedAt)
    }
}
