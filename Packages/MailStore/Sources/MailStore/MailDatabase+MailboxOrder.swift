import Foundation
import GRDB
import MailCore

/// Every mailbox reads newest first straight from an index. A label's mailbox orders by the thread's date, which
/// lives on `thread`, so each label row keeps a copy of it: then one index on the label row both finds the label's
/// threads and lists them in order, and SQLite stops at the first screenful instead of sorting the whole label.
extension MailDatabase {
    /// v39: copies each thread's date onto its label rows and indexes every mailbox's order.
    static func orderMailboxes(_ db: Database) throws {
        // Rebuilt rather than altered, so the copy can't be left out: SQLite only adds a NOT NULL column with a
        // default, which a row written without the date would take silently.
        try db.create(table: "newThreadLabel") { table in
            table.column("accountID", .text).notNull()
            table.column("threadID", .text).notNull()
            table.column("labelID", .text).notNull()
            // The thread's date, kept in step by `replaceLabels` and the trigger below.
            table.column("date", .datetime).notNull()
            table.primaryKey(["accountID", "threadID", "labelID"])
            table.foreignKey(["accountID", "threadID"], references: "thread", onDelete: .cascade)
        }
        try db.execute(
            sql: """
                INSERT INTO newThreadLabel (accountID, threadID, labelID, date)
                SELECT threadLabel.accountID, threadLabel.threadID, threadLabel.labelID, thread.date FROM threadLabel
                JOIN thread ON thread.accountID = threadLabel.accountID AND thread.id = threadLabel.threadID
                """)
        try db.drop(table: "threadLabel")
        try db.rename(table: "newThreadLabel", to: "threadLabel")
        // A label in every account the Focus shows, and in one account.
        try db.create(index: "threadLabel_byLabelDate", on: "threadLabel", columns: ["labelID", "date"])
        try db.create(index: "threadLabel_byLabel", on: "threadLabel", columns: ["labelID", "accountID", "date"])
        // All Mail in one account, and the account's newest threads without bodies; `thread_byDate` serves every
        // account's.
        try db.create(index: "thread_byAccountDate", on: "thread", columns: ["accountID", "date"])
        // Any write that redates a thread without rewriting its labels.
        try db.execute(
            sql: """
                CREATE TRIGGER threadLabel_followsThreadDate AFTER UPDATE OF date ON thread
                WHEN NEW.date IS NOT OLD.date
                BEGIN
                    UPDATE threadLabel SET date = NEW.date WHERE accountID = NEW.accountID AND threadID = NEW.id;
                END
                """)
    }

    /// Sets a stored thread's labels, each with the thread's date beside it. Every label row is written here; a
    /// thread that isn't stored gets none. Only the labels that changed are written: a row kept keeps its rowid, which
    /// breaks ties between threads of the same date, so rewriting a thread doesn't move it past its neighbours. The
    /// trigger has already brought a kept row's date up to the thread's.
    static func replaceLabels(of thread: ThreadSummary.ID, with labels: Set<String>, in db: Database) throws {
        let id: StatementArguments = [thread.accountID.rawValue, thread.threadID]
        let wanted: StatementArguments = [String(decoding: try JSONEncoder().encode(labels.sorted()), as: UTF8.self)]
        try db.execute(
            sql: """
                DELETE FROM threadLabel WHERE accountID = ? AND threadID = ?
                AND labelID NOT IN (SELECT value FROM json_each(?))
                """,
            arguments: id + wanted)
        guard !labels.isEmpty else { return }
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO threadLabel (accountID, threadID, labelID, date)
                SELECT thread.accountID, thread.id, label.value, thread.date FROM thread, json_each(?) AS label
                WHERE thread.accountID = ? AND thread.id = ?
                """,
            arguments: wanted + id)
    }
}
