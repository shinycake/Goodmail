import Foundation
import GRDB
public import MailCore

/// What the reader decided about senders (ADR-038): who is a VIP, and Block Sender's rules.
extension MailDatabase {
    public func vips() throws -> VIPList {
        try pool.read(Self.vips)
    }

    /// The VIPs. Emits now and after every change.
    public func vipList() -> AsyncThrowingStream<VIPList, any Error> {
        observe(Self.vips)
    }

    /// Makes `sender` a VIP, last, or no longer one.
    public func setVIP(_ sender: SenderAddress, _ isVIP: Bool) throws {
        try write { db in
            var vips = try Self.vips(db)
            vips.set(sender, isVIP: isVIP)
            try Self.setVIPs(vips, in: db)
        }
    }

    /// Writes Block Sender's rule for `sender`, called `name`, first in the rules (`RuleBook.blocking`). Rules this
    /// build can't read stay as they are, after it.
    public func block(_ sender: SenderAddress, named name: String) throws {
        try write { db in
            let stored = try MailRuleRecord.order(Column("position")).fetchAll(db)
            let readable = stored.compactMap(\.rule)
            let rules = RuleBook.blocking(sender, named: name, in: readable)
            try MailRuleRecord.filter(keys: readable.map(\.id.uuidString)).deleteAll(db)
            let unreadable = stored.filter { $0.rule == nil }
            for (position, record) in unreadable.enumerated() {
                var record = record
                record.position = rules.count + position
                try record.update(db)
            }
            for (position, rule) in rules.enumerated() { try MailRuleRecord(rule, position: position).insert(db) }
        }
    }

    static func vips(_ db: Database) throws -> VIPList {
        VIPList(try String.fetchAll(db, sql: "SELECT address FROM vip ORDER BY position"))
    }

    /// Makes `vips` the VIPs, in their order, within the transaction `db` is in.
    static func setVIPs(_ vips: VIPList, in db: Database) throws {
        try db.execute(sql: "DELETE FROM vip")
        for (position, address) in vips.addresses.enumerated() {
            try db.execute(sql: "INSERT INTO vip (address, position) VALUES (?, ?)", arguments: [address, position])
        }
    }

    /// The VIPs' addresses, lowercased, in the order they were added.
    static func createVIPs(_ db: Database) throws {
        try db.create(table: "vip") { table in
            table.primaryKey("address", .text)
            table.column("position", .integer).notNull()
        }
    }
}
