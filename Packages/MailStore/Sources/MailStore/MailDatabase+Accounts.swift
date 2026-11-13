import Foundation
import GRDB
import MailCore

extension MailDatabase {
    public func save(_ account: Account) throws {
        try write { db in try AccountRecord(account).save(db) }
    }

    /// In the order they were added.
    public func accounts() throws -> [Account] {
        try pool.read { db in
            try AccountRecord.order(Column("createdAt")).fetchAll(db).compactMap(\.account)
        }
    }

    /// Takes the account off the device with everything stored for it: mail, labels, sync state and queued work.
    public func removeAccount(_ account: AccountID) throws {
        try write { db in
            for table in ["outbox", "outgoing"] {
                try db.execute(sql: "DELETE FROM \(table) WHERE accountID = ?", arguments: [account.rawValue])
            }
            // Threads, their labels and messages, labels and sync state go with it (foreign keys cascade).
            try db.execute(sql: "DELETE FROM account WHERE id = ?", arguments: [account.rawValue])
        }
    }

    /// The signature the account's provider adds to new mail, as plain text.
    public func signature(for account: AccountID) throws -> String? {
        try pool.read { db in
            try String.fetchOne(db, sql: "SELECT signature FROM account WHERE id = ?", arguments: [account.rawValue])
        }
    }
}

struct AccountRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "account"

    var id: String
    var email: String
    var color: String
    var service: String
    var createdAt: Date

    init(_ account: Account, createdAt: Date = .now) {
        id = account.id.rawValue
        email = account.email
        color = account.color.rawValue
        service = account.service.rawValue
        self.createdAt = createdAt
    }

    /// `nil` if the stored color is no longer offered, or the service isn't one this build knows.
    var account: Account? {
        guard let color = AccountColor(rawValue: color), let service = MailService(rawValue: service) else {
            return nil
        }
        return Account(id: AccountID(rawValue: id), email: email, color: color, service: service)
    }
}
