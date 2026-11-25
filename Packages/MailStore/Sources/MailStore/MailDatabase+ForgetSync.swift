import GRDB
public import MailCore

extension MailDatabase {
    /// Forgets how far the account was synced and the changes and messages queued or uploading for it, as for a copy
    /// that fell out of date: the watch's own, while the owner had "Mail Without iPhone" off (ADR-023). Its threads
    /// stay until the next sync, which starts afresh and sweeps out the ones it no longer sees.
    public func forgetSync(of account: AccountID) throws {
        try write { db in try Self.forgetSync(of: account.rawValue, in: db) }
    }

    static func forgetSync(of account: String, in db: Database) throws {
        for table in ["outbox", "outgoing", "syncState"] {
            try db.execute(sql: "DELETE FROM \(table) WHERE accountID = ?", arguments: [account])
        }
    }
}
