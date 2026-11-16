import Foundation
import GRDB
public import MailCore

extension MailDatabase {
    /// Follows the Focus filter the system sets as the Focus changes. Every blended view follows at once.
    public func apply(_ focus: FocusFilter) throws {
        try write { db in
            switch focus {
            case .everyAccount:
                try db.execute(sql: "UPDATE account SET inFocus = 1")
            case .accounts(let accounts):
                try db.execute(
                    sql: "UPDATE account SET inFocus = id IN (SELECT value FROM json_each(?))",
                    arguments: [String(decoding: try JSONEncoder().encode(accounts.map(\.rawValue)), as: UTF8.self)])
            }
        }
    }

    /// The Focus filter in effect.
    public func focusFilter() throws -> FocusFilter {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, inFocus FROM account")
            let inFocus = Set(rows.filter { $0["inFocus"] }.map { AccountID(rawValue: $0["id"]) })
            return inFocus.count == rows.count ? .everyAccount : .accounts(inFocus)
        }
    }

    static func isInFocus(_ account: AccountID, in db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT inFocus FROM account WHERE id = ?", arguments: [account.rawValue]) ?? false
    }
}
