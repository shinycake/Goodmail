import Foundation
import GRDB
public import MailCore

#if canImport(os)
    import os
#endif

/// The messages minimized at the bottom of each window, kept as written so the bar comes back after the app is
/// closed. Each window is named by an identifier the app picks, and keeps its own list.
extension MailDatabase {
    /// Makes `drafts`, the last one written first, the minimized messages of `window`, replacing what it had. A draft
    /// another window had moves to this one.
    public func keepMinimizedDrafts(_ drafts: [Draft], for window: String) throws {
        let rows = try drafts.enumerated().map { position, draft in
            [draft.id.uuidString, window, position, draft.accountID.rawValue, try Self.minimizedColumn(draft)]
                as StatementArguments
        }
        try write { db in
            try db.execute(sql: "DELETE FROM minimizedDraft WHERE window = ?", arguments: [window])
            for row in rows {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO minimizedDraft (draftID, window, position, accountID, draft)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: row)
            }
        }
    }

    /// The minimized messages of every window but those `open`, which now belong to `window`, in the order kept.
    /// The first window after a launch takes them all, since the windows they were minimized in are gone. A draft
    /// that no longer reads, as after a change to how drafts are kept, is left out so the rest still come back; it
    /// goes the next time this window keeps its drafts.
    public func claimMinimizedDrafts(for window: String, sparing open: Set<String> = []) throws -> [Draft] {
        let decoder = JSONDecoder()
        let kept = Array(open.subtracting([window]))
        let others = kept.isEmpty ? "" : "WHERE window NOT IN (\(databaseQuestionMarks(count: kept.count)))"
        return try write { db in
            try db.execute(
                sql: "UPDATE minimizedDraft SET window = ? \(others)",
                arguments: StatementArguments([window] + kept))
            return try String.fetchAll(
                db, sql: "SELECT draft FROM minimizedDraft WHERE window = ? ORDER BY position, rowid",
                arguments: [window])
        }.compactMap { column in
            do {
                return try decoder.decode(Draft.self, from: Data(column.utf8))
            } catch {
                #if canImport(os)
                    Logger(subsystem: "com.idanbirman.goodmail", category: "drafts")
                        .error("A minimized draft didn't read and was left out: \(error, privacy: .public)")
                #endif
                return nil
            }
        }
    }

    private static func minimizedColumn(_ draft: Draft) throws -> String {
        String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
    }
}
