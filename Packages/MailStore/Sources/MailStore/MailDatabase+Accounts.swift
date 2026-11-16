import Foundation
import GRDB
import MailCore

extension MailDatabase {
    /// Stores the account. A new one goes after the others; one stored before keeps its place.
    public func save(_ account: Account) throws {
        try write { db in
            let position =
                try Int.fetchOne(db, sql: "SELECT position FROM account WHERE id = ?", arguments: [account.id.rawValue])
                ?? Int.fetchOne(db, sql: "SELECT MAX(position) + 1 FROM account") ?? 0
            try AccountRecord(account, position: position).save(db)
        }
    }

    /// Changes the account's name and color. Its mail and its place among the accounts stay as they are.
    public func update(_ account: Account) throws {
        try write { db in
            try db.execute(
                sql: "UPDATE account SET name = ?, color = ? WHERE id = ?",
                arguments: [account.name, account.color.rawValue, account.id.rawValue])
        }
    }

    /// In the order the reader put them, which starts as the order they were added.
    public func accounts() throws -> [Account] {
        try pool.read { db in
            try AccountRecord.order(Column("position"), Column("createdAt")).fetchAll(db).compactMap(\.account)
        }
    }

    /// Puts the accounts in `order`. Any it leaves out follow, in the order they had.
    public func reorderAccounts(_ order: [AccountID]) throws {
        try write { db in
            // Every account moves past the places `order` takes, keeping its order, and then the named ones take them.
            try db.execute(sql: "UPDATE account SET position = position + ?", arguments: [order.count])
            for (position, id) in order.enumerated() {
                try db.execute(sql: "UPDATE account SET position = ? WHERE id = ?", arguments: [position, id.rawValue])
            }
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
    var name: String?
    var aliases: [Contact]
    var createdAt: Date
    var position: Int

    init(_ account: Account, position: Int, createdAt: Date = .now) {
        id = account.id.rawValue
        email = account.email
        color = account.color.rawValue
        service = account.service.rawValue
        name = account.name
        aliases = account.aliases
        self.createdAt = createdAt
        self.position = position
    }

    /// `nil` if the stored color is no longer offered, or the service isn't one this build knows.
    var account: Account? {
        guard let color = AccountColor(rawValue: color), let service = MailService(rawValue: service) else {
            return nil
        }
        return Account(
            id: AccountID(rawValue: id), email: email, color: color, service: service, name: name, aliases: aliases)
    }
}
