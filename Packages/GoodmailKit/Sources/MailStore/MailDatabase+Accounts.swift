import Foundation
import GRDB
import MailCore

extension MailDatabase {
    public func save(_ account: Account) throws {
        try pool.write { db in try AccountRecord(account).save(db) }
    }

    /// In the order they were added.
    public func accounts() throws -> [Account] {
        try pool.read { db in
            try AccountRecord.order(Column("createdAt")).fetchAll(db).compactMap(\.account)
        }
    }
}

struct AccountRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "account"

    var id: String
    var email: String
    var color: String
    var createdAt: Date

    init(_ account: Account, createdAt: Date = .now) {
        id = account.id.rawValue
        email = account.email
        color = account.color.rawValue
        self.createdAt = createdAt
    }

    /// `nil` if the stored color is no longer offered.
    var account: Account? {
        AccountColor(rawValue: color).map { Account(id: AccountID(rawValue: id), email: email, color: $0) }
    }
}
