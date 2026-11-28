import Foundation
import GRDB
public import MailCore

/// The reader's smart mailboxes (ADR-039): the boxes in their sidebar order, and the conversations each
/// holds, read from the mail on the device.
extension MailDatabase {
    public func smartMailboxes() throws -> [SmartMailbox] {
        try read(Self.smartMailboxes)
    }

    /// Makes `boxes` the smart mailboxes, in this order.
    public func setSmartMailboxes(_ boxes: [SmartMailbox]) throws {
        try write { db in
            try SmartMailboxRecord.deleteAll(db)
            for (position, box) in boxes.enumerated() { try SmartMailboxRecord(box, position: position).insert(db) }
        }
    }

    /// Stores `box` in its place, or after the others when it's new, and makes `vips` the VIPs when given, in one
    /// transaction, as the editor of the VIPs box saves both.
    public func saveSmartMailbox(_ box: SmartMailbox, vips: VIPList? = nil) throws {
        try write { db in
            let position =
                try Int.fetchOne(
                    db, sql: "SELECT position FROM smartMailbox WHERE id = ?", arguments: [box.id.rawValue])
                ?? (Int.fetchOne(db, sql: "SELECT MAX(position) + 1 FROM smartMailbox") ?? 0)
            try SmartMailboxRecord(box, position: position).save(db)
            if let vips { try Self.setVIPs(vips, in: db) }
        }
    }

    public func deleteSmartMailbox(_ id: SmartMailbox.ID) throws {
        try write { db in _ = try SmartMailboxRecord.deleteOne(db, key: id.rawValue) }
    }

    static func smartMailboxes(_ db: Database) throws -> [SmartMailbox] {
        try SmartMailboxRecord.order(Column("position")).fetchAll(db).compactMap(\.smartMailbox)
    }

    /// The table, with the starting set (`SmartMailbox.startingSet`) in them. Every device starts with the same
    /// boxes under the same IDs, so the settings sync sees one copy of each.
    static func createSmartMailboxes(_ db: Database) throws {
        try db.create(table: "smartMailbox") { table in
            table.primaryKey("id", .text)
            table.column("position", .integer).notNull()
            table.column("json", .text).notNull()
        }
        for (position, box) in SmartMailbox.startingSet.enumerated() {
            try SmartMailboxRecord(box, position: position).insert(db)
        }
    }
}

extension MailFollowing {
    /// The boxes in their order, with each one's unread conversations. Emits now and after every change.
    /// `mailboxNames` names the standard mailboxes, as `MailDatabase.messageFacts` takes them.
    public func smartMailboxDirectory(mailboxNames: [String: String] = [:])
        -> AsyncThrowingStream<SmartMailboxDirectory, any Error>
    {
        followed.observe { db in
            let boxes = try MailDatabase.smartMailboxes(db)
            let vips = try MailDatabase.vips(db)
            let unread = try SmartMatch(db, mailboxNames: mailboxNames, context: MailCondition.Context()).threads(
                meeting: Dictionary(uniqueKeysWithValues: boxes.map { ($0.id, $0.condition(vips: vips)) }),
                unreadOnly: true)
            return SmartMailboxDirectory(
                mailboxes: boxes, unreadCounts: unread.compactMapValues { $0.isEmpty ? nil : $0.count })
        }
    }

    /// The conversations in the box, newest first, as the box is defined at each change: an edit from another device
    /// shows at once, and a deleted box shows none. Emits now and after every change.
    public func threads(inSmartMailbox id: SmartMailbox.ID, mailboxNames: [String: String] = [:])
        -> AsyncThrowingStream<[ThreadSummary], any Error>
    {
        followed.observe { db in
            guard let box = try MailDatabase.smartMailboxes(db).first(where: { $0.id == id }) else { return [] }
            let condition = box.condition(vips: try MailDatabase.vips(db))
            return try SmartMatch(db, mailboxNames: mailboxNames, context: MailCondition.Context())
                .threads(meeting: [id: condition], unreadOnly: false)[id] ?? []
        }
    }
}

struct SmartMailboxRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "smartMailbox"

    var id: String
    var position: Int
    /// The `SmartMailbox`, as JSON with its keys sorted, so the same box is stored the same on every device and the
    /// settings sync sees no change in it.
    var json: String

    init(_ box: SmartMailbox, position: Int) throws {
        id = box.id.rawValue
        self.position = position
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        json = String(decoding: try encoder.encode(box), as: UTF8.self)
    }

    /// `nil` for a box this build can't read, as one with a condition from a newer build: it is left out.
    var smartMailbox: SmartMailbox? {
        try? JSONDecoder().decode(SmartMailbox.self, from: Data(json.utf8))
    }
}
