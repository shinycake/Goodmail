import GRDB

/// Constraints that keep a row's columns to the states they model, so a row the code can't read can't be written.
/// SQLite adds a CHECK only with the table, so each table is made again with its rows.
extension MailDatabase {
    static func checkDeliveriesAndSnoozeKeepers(_ db: Database) throws {
        // A message both failed and uploading read as neither, and stopped its account's queue. Kept as failed, which
        // the writer sees and sends again or deletes, rather than as uploading, which could send it twice.
        try db.create(table: "outgoingChecked") { table in
            table.column("id", .text).primaryKey()
            table.column("accountID", .text).notNull()
            table.column("sendAt", .datetime).notNull()
            table.column("failure", .text)
            table.column("draft", .jsonText).notNull()
            table.column("purpose", .text).notNull().defaults(to: "send")
            table.column("upload", .text)
            table.check(sql: "failure IS NULL OR upload IS NULL")
        }
        try db.execute(
            sql: """
                INSERT INTO outgoingChecked (id, accountID, sendAt, failure, draft, purpose, upload)
                SELECT id, accountID, sendAt, failure, draft, purpose, CASE WHEN failure IS NULL THEN upload END
                FROM outgoing
                """)
        try db.drop(table: "outgoing")
        try db.rename(table: "outgoingChecked", to: "outgoing")

        // An asleep row without a keeper read as another device's, so no device alerted for it. Every snooze is made
        // with one; one that lost it is this device's, as `v34-snooze-keeper` took every snooze before it to be.
        try db.create(table: "snoozeChecked") { table in
            table.column("accountID", .text).notNull().references("account", onDelete: .cascade)
            table.column("threadID", .text).notNull()
            table.column("wakeAt", .datetime)
            table.column("wokeAt", .datetime)
            table.column("keeper", .text)
            table.primaryKey(["accountID", "threadID"])
            table.check(sql: "(wakeAt IS NULL) != (wokeAt IS NULL)")
            table.check(sql: "(wakeAt IS NULL) = (keeper IS NULL)")
        }
        try db.execute(
            sql: """
                INSERT INTO snoozeChecked (accountID, threadID, wakeAt, wokeAt, keeper)
                SELECT accountID, threadID, wakeAt, wokeAt,
                    CASE WHEN wakeAt IS NULL THEN NULL ELSE COALESCE(keeper, 'thisDevice') END
                FROM snooze
                """)
        try db.drop(table: "snooze")
        try db.rename(table: "snoozeChecked", to: "snooze")
        try db.create(index: "snooze_byWake", on: "snooze", columns: ["wakeAt"])
    }
}
