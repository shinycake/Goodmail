public import Foundation
import GRDB
public import MailCore

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
        try writeUnannounced { db in
            try db.execute(
                sql: "UPDATE message SET accessedAt = ? WHERE accountID = ? AND threadID = ?",
                arguments: [date, thread.accountID.rawValue, thread.threadID])
        }
    }

    /// The cache's size now. `attachments` is the folder the attachment files are kept in, if any.
    public func cacheUsage(attachments: URL? = nil) throws -> CacheUsage {
        let bodies = try read { db in try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(size), 0) FROM message") ?? 0
        }
        return CacheUsage(
            bodies: bodies, attachments: Self.attachmentFolders(in: attachments).reduce(0) { $0 + $1.size })
    }

    /// Whether the cached bodies leave room to prefetch more under `limit`. Prefetch stops at nine tenths of it, so it
    /// never fetches what the cap would evict at once, and a run after an eviction doesn't fetch the same mail again.
    /// A cache that can't be measured doesn't stop it.
    public func hasRoomToPrefetch(under limit: Int) -> Bool {
        guard let bodies = try? cacheUsage().bodies else { return true }
        return bodies < limit / 10 * 9
    }

    /// Evicts the least recently read bodies (a thread's together) and attachment files until the cache fits
    /// `limit`. Threads with a draft or a queued action are never evicted, though they count toward the size.
    ///
    /// Bodies are chosen and deleted in one transaction, so a draft or an action queued meanwhile keeps its thread.
    /// Attachment files go after it; one that can't be removed stays counted, and the next trim tries again.
    @discardableResult
    public func trimCache(to limit: Int = MailDatabase.cacheLimit, attachments: URL? = nil) throws -> CacheTrim {
        let folders = Self.attachmentFolders(in: attachments)
        let (threads, chosenFolders) = try writeUnannounced { db in
            let bodies = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(size), 0) FROM message") ?? 0
            let excess = bodies + folders.reduce(0) { $0 + $1.size } - limit
            guard excess > 0 else { return ([EvictableThread](), [AttachmentFolder]()) }
            let plan = Self.evictionPlan(threads: try Self.evictableThreads(in: db), folders: folders, excess: excess)
            for thread in plan.threads {
                try db.execute(
                    sql: "DELETE FROM message WHERE accountID = ? AND threadID = ?",
                    arguments: [thread.accountID, thread.threadID])
            }
            return plan
        }
        if !threads.isEmpty { signal.post() }

        var trim = CacheTrim(threads: threads.count, freedBytes: threads.reduce(0) { $0 + $1.size })
        for folder in chosenFolders where (try? FileManager.default.removeItem(at: folder.url)) != nil {
            trim.attachments += 1
            trim.freedBytes += folder.size
        }
        return trim
    }

    /// The least recently read threads and attachment folders that together free at least `excess` bytes.
    private static func evictionPlan(threads: [EvictableThread], folders: [AttachmentFolder], excess: Int) -> (
        threads: [EvictableThread], folders: [AttachmentFolder]
    ) {
        enum Candidate {
            case thread(EvictableThread)
            case attachment(AttachmentFolder)
            var accessedAt: Date {
                switch self {
                case .thread(let thread): thread.accessedAt
                case .attachment(let folder): folder.accessedAt
                }
            }
            var size: Int {
                switch self {
                case .thread(let thread): thread.size
                case .attachment(let folder): folder.size
                }
            }
        }
        var plan: (threads: [EvictableThread], folders: [AttachmentFolder]) = ([], [])
        var excess = excess
        let candidates = (threads.map(Candidate.thread) + folders.map(Candidate.attachment))
            .sorted { $0.accessedAt < $1.accessedAt }
        for candidate in candidates where excess > 0 {
            excess -= candidate.size
            switch candidate {
            case .thread(let thread): plan.threads.append(thread)
            case .attachment(let folder): plan.folders.append(folder)
            }
        }
        return plan
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

extension MailDatabase: ThreadFetchStore {
    /// Whether thread `t`, with its `accountID`, `id` and `date`, lacks bodies.
    ///
    /// A thread whose cached bodies stop short of its date by more than a second lacks a newer message. The store
    /// keeps the thread's date to the millisecond and each message's whole, so a second is allowed.
    ///
    /// One whose bodies were fetched more than an hour after its date counts as whole even so: a message the provider
    /// leaves out of the thread, such as a draft, must not have it fetched again on every run. A message that arrives
    /// later than that after it was written is fetched when its thread opens.
    ///
    /// The newest date comes from the message index alone; `fetchedAt`, stored past each body, is read only for the
    /// few threads that are behind.
    private static let lacksBodies = """
        (NOT EXISTS (SELECT 1 FROM message m WHERE m.accountID = t.accountID AND m.threadID = t.id)
            OR (julianday((
                    SELECT MAX(m.date) FROM message m WHERE m.accountID = t.accountID AND m.threadID = t.id
                )) < julianday(t.date) - 1.0 / 86400
                AND julianday((
                    SELECT MAX(m.fetchedAt) FROM message m WHERE m.accountID = t.accountID AND m.threadID = t.id
                )) < julianday(t.date) + 1.0 / 24))
        """

    public func threadsMissingBodies(account: AccountID, among newest: Int) throws -> [ThreadSummary.ID] {
        try read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM (
                        SELECT t.accountID, t.id, t.date FROM thread t
                        WHERE t.accountID = ? AND NOT EXISTS (
                            SELECT 1 FROM threadLabel l
                            WHERE l.accountID = t.accountID AND l.threadID = t.id AND l.labelID IN (?, ?))
                        ORDER BY t.date DESC
                        LIMIT ?
                    ) AS t
                    WHERE \(Self.lacksBodies)
                    ORDER BY date DESC
                    """,
                arguments: [account.rawValue, SystemLabel.spam, SystemLabel.trash, newest]
            ).map { ThreadSummary.ID(accountID: account, threadID: $0) }
        }
    }

    public func threadsMissingBodies(among threads: [ThreadSummary.ID]) throws -> [ThreadSummary.ID] {
        let missing = try read { db in
            try Dictionary(grouping: threads, by: \.accountID).flatMap { account, threads in
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT t.id FROM thread t
                        WHERE t.accountID = ? AND t.id IN (\(databaseQuestionMarks(count: threads.count)))
                            AND \(Self.lacksBodies)
                        """,
                    arguments: StatementArguments([account.rawValue] + threads.map(\.threadID))
                ).map { ThreadSummary.ID(accountID: account, threadID: $0) }
            }
        }
        let lacking = Set(missing)
        return threads.filter { lacking.contains($0) }
    }

    public func savePrefetched(_ messages: [Message], inThread thread: ThreadSummary.ID, fetchedAt: Date) throws {
        // Dated by the mail, not the fetch: prefetching shouldn't make bodies look more read than any the reader opened.
        var accessedAt = min(messages.map(\.date).max() ?? fetchedAt, fetchedAt)
        // Unless the reader opened the thread while it was being fetched.
        let read = try read { db in
            try Date.fetchOne(
                db, sql: "SELECT MAX(accessedAt) FROM message WHERE accountID = ? AND threadID = ?",
                arguments: [thread.accountID.rawValue, thread.threadID])
        }
        if let read { accessedAt = max(accessedAt, read) }
        try save(messages, inThread: thread, fetchedAt: fetchedAt, accessedAt: accessedAt)
    }
}
