import Foundation
public import MailCore

/// The settings the database keeps that follow the reader to their other devices (`SettingsSync`), one group each.
/// Each account's setting is an element named by the account's ID, which is the same on every device; a device
/// without the account leaves it alone.
extension OffMainDatabase {
    /// The families read and write on the settings sync's actor, so they take the blocking database.
    public var syncedSettings: [any SettingsFamily] {
        [
            SyncedSignatures(database: blocking), SyncedAlerts(database: blocking), SyncedBadges(database: blocking),
            SyncedRules(database: blocking), SyncedSmartMailboxes(database: blocking), SyncedVIPs(database: blocking),
        ]
    }
}

extension MailDatabase {
    /// The names the database's groups are shared under.
    public enum SyncedGroup {
        public static let signatures = "signatures"
        public static let alerts = "alerts"
        public static let badges = "badges"
        public static let rules = "rules"
        public static let smartMailboxes = "smartMailboxes"
        public static let vips = "vips"
    }
}

/// The signatures of accounts whose service doesn't keep one: Gmail's travels with the account itself.
struct SyncedSignatures: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedGroup.signatures

    func local() throws -> LocalSettings {
        let accounts = try database.accounts().filter { !$0.service.syncsSignature }
        var values: [String: Data] = [:]
        for account in accounts {
            guard let signature = try database.signature(for: account.id), !signature.isEmpty else { continue }
            values[account.id.rawValue] = Data(signature.utf8)
        }
        return LocalSettings(values, scope: .only(Set(accounts.map(\.id.rawValue))))
    }

    func apply(_ changes: [String: SettingChange]) throws {
        for (id, change) in changes {
            let signature =
                switch change {
                case .set(let data): String(decoding: data, as: UTF8.self)
                case .removed: ""
                }
            try database.apply(StoreChanges(accountID: AccountID(rawValue: id), signature: signature))
        }
    }
}

/// Which mail alerts, for each account.
struct SyncedAlerts: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedGroup.alerts

    func local() throws -> LocalSettings {
        let ids = try database.accounts().map(\.id)
        var values: [String: Data] = [:]
        for id in ids { values[id.rawValue] = Data(try database.notifications(for: id, now: .now).level.rawValue.utf8) }
        return LocalSettings(values, scope: .only(Set(ids.map(\.rawValue))))
    }

    func apply(_ changes: [String: SettingChange]) throws {
        for case (let id, .set(let data)) in changes {
            // A level from a newer build is left for the build that knows it.
            guard let level = NotificationLevel(rawValue: String(decoding: data, as: UTF8.self)) else { continue }
            try database.setNotificationLevel(level, for: AccountID(rawValue: id), now: .now)
        }
    }
}

/// What each account counts toward the app badge.
struct SyncedBadges: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedGroup.badges

    func local() throws -> LocalSettings {
        let ids = try database.accounts().map(\.id)
        let sources = try database.badgeSources()
        var values: [String: Data] = [:]
        for id in ids { values[id.rawValue] = Data((sources[id] ?? .initial).rawValue.utf8) }
        return LocalSettings(values, scope: .only(Set(ids.map(\.rawValue))))
    }

    func apply(_ changes: [String: SettingChange]) throws {
        for case (let id, .set(let data)) in changes {
            guard let source = BadgeSource(rawValue: String(decoding: data, as: UTF8.self)) else { continue }
            try database.setBadgeSource(source, for: AccountID(rawValue: id))
        }
    }
}

/// The reader's mail rules, each an element with its place in the order, so rules added on two devices both stay.
struct SyncedRules: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedGroup.rules

    /// A rule as it's shared.
    private struct Placed: Codable {
        var position: Int
        var rule: MailRule
    }

    func local() throws -> LocalSettings {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var values: [String: Data] = [:]
        for (position, rule) in try database.rules().enumerated() {
            values[rule.id.uuidString] = try encoder.encode(Placed(position: position, rule: rule))
        }
        return LocalSettings(values)
    }

    func apply(_ changes: [String: SettingChange]) throws {
        var placed = Dictionary(
            uniqueKeysWithValues: try database.rules().enumerated().map {
                ($0.element.id.uuidString, Placed(position: $0.offset, rule: $0.element))
            })
        for (id, change) in changes {
            switch change {
            case .set(let data):
                // A rule a newer build wrote in a form this one can't read is left as it is here.
                guard let rule = try? JSONDecoder().decode(Placed.self, from: data) else { continue }
                placed[id] = rule
            case .removed:
                placed[id] = nil
            }
        }
        let ordered = placed.values.sorted {
            ($0.position, $0.rule.id.uuidString) < ($1.position, $1.rule.id.uuidString)
        }
        try database.setRules(ordered.map(\.rule))
    }
}
