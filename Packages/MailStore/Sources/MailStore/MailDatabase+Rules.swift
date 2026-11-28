public import Foundation
import GRDB
public import MailCore

/// The reader's mail rules, and how far each account's arrived mail has been through them (`RuleRunner`).
extension MailDatabase: RuleStore {
    public func rules() throws -> [MailRule] {
        try read { db in
            try MailRuleRecord.order(Column("position")).fetchAll(db).compactMap(\.rule)
        }
    }

    /// Makes `rules` the rules, in this order.
    public func setRules(_ rules: [MailRule]) throws {
        try write { db in
            try MailRuleRecord.deleteAll(db)
            for (position, rule) in rules.enumerated() { try MailRuleRecord(rule, position: position).insert(db) }
        }
    }

    public func claimRuleMail(in account: AccountID, now: Date, limit: Int) throws -> [ThreadSummary.ID] {
        try write { db in
            guard
                let through = try Date.fetchOne(
                    db, sql: "SELECT through FROM ruleProgress WHERE accountID = ?", arguments: [account.rawValue])
            else {
                try db.execute(
                    sql: "INSERT INTO ruleProgress (accountID, through) VALUES (?, ?)",
                    arguments: [account.rawValue, now])
                return []
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT thread.id, thread.date FROM thread
                    WHERE thread.accountID = ? AND thread.date > ?
                        AND NOT EXISTS (
                            SELECT 1 FROM threadLabel
                            WHERE threadLabel.accountID = thread.accountID AND threadLabel.threadID = thread.id
                                AND threadLabel.labelID IN (?, ?, ?))
                    ORDER BY thread.date ASC LIMIT ?
                    """,
                arguments: [
                    account.rawValue, through, SystemLabel.spam, SystemLabel.trash, SystemLabel.draft, limit,
                ])
            guard let newest = rows.last.map({ $0["date"] as Date }) else { return [] }
            try db.execute(
                sql: "UPDATE ruleProgress SET through = ? WHERE accountID = ?", arguments: [newest, account.rawValue])
            return rows.map { ThreadSummary.ID(accountID: account, threadID: $0["id"]) }
        }
    }
}

struct MailRuleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "mailRule"

    var id: String
    var position: Int
    /// The `MailRule`, as JSON.
    var json: String

    init(_ rule: MailRule, position: Int) throws {
        id = rule.id.uuidString
        self.position = position
        json = String(decoding: try JSONEncoder().encode(rule), as: UTF8.self)
    }

    /// `nil` for a rule this build can't read, as one with a condition from a newer build: it is left out, not run.
    var rule: MailRule? {
        try? JSONDecoder().decode(MailRule.self, from: Data(json.utf8))
    }
}
