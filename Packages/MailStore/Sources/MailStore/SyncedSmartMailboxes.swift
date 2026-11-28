import Foundation
import GRDB
import MailCore

/// The reader's smart mailboxes, each an element named by its ID with its place in the order, so boxes added on two
/// devices both stay and an edit replaces the box everywhere (ADR-039). A box is shared as stored, so one a newer
/// build wrote, which this build can't read, still travels and isn't taken for removed.
struct SyncedSmartMailboxes: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedGroup.smartMailboxes

    /// A box as it's shared: its place and the stored form.
    private struct Placed: Codable {
        var position: Int
        var box: String
    }

    func local() throws -> LocalSettings {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var values: [String: Data] = [:]
        for record in try records() {
            values[record.id] = try encoder.encode(Placed(position: record.position, box: record.json))
        }
        return LocalSettings(values)
    }

    func apply(_ changes: [String: SettingChange]) throws {
        var placed = Dictionary(
            uniqueKeysWithValues: try records().map { ($0.id, Placed(position: $0.position, box: $0.json)) })
        for (id, change) in changes {
            switch change {
            case .set(let data):
                guard let box = try? JSONDecoder().decode(Placed.self, from: data) else { continue }
                placed[id] = box
            case .removed:
                placed[id] = nil
            }
        }
        let ordered = placed.sorted { ($0.value.position, $0.key) < ($1.value.position, $1.key) }
        try database.write { db in
            try SmartMailboxRecord.deleteAll(db)
            for (position, (id, box)) in ordered.enumerated() {
                try db.execute(
                    sql: "INSERT INTO smartMailbox (id, position, json) VALUES (?, ?, ?)",
                    arguments: [id, position, box.box])
            }
        }
    }

    private func records() throws -> [SmartMailboxRecord] {
        try database.read { db in try SmartMailboxRecord.order(Column("position")).fetchAll(db) }
    }
}

/// The VIPs (`VIPList`, ADR-038), each address an element, so a VIP added on one device and another added elsewhere
/// both stay. A new VIP from another device goes last, in the order of the addresses.
struct SyncedVIPs: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedGroup.vips

    func local() throws -> LocalSettings {
        LocalSettings(Dictionary(uniqueKeysWithValues: try database.vips().addresses.map { ($0, Data()) }))
    }

    func apply(_ changes: [String: SettingChange]) throws {
        try database.write { db in
            var vips = try MailDatabase.vips(db)
            for (address, change) in changes.sorted(by: { $0.key < $1.key }) {
                guard let sender = SenderAddress(address) else { continue }
                switch change {
                case .set: vips.set(sender, isVIP: true)
                case .removed: vips.set(sender, isVIP: false)
                }
            }
            try MailDatabase.setVIPs(vips, in: db)
        }
    }
}
