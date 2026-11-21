public import Foundation
public import MailCore

/// The mail state the database keeps that follows the reader to their other devices (ADR-037): pins, snoozes and
/// mutes kept on the device, one group each. Each thread is an element named by `ThreadSummary.ID.syncedElement`,
/// and a device leaves alone the threads of accounts it doesn't have.
extension MailDatabase {
    public var syncedMailState: [any SettingsFamily] {
        [SyncedPins(database: self), SyncedSnoozes(database: self), SyncedMutes(database: self)]
    }

    /// The names the mail state's groups are shared under.
    public enum SyncedMailGroup {
        public static let pins = "pins"
        public static let snoozes = "snoozes"
        public static let mutes = "deviceMutes"
    }
}

/// What a pin or a mute shares: only that the thread has one.
private let present = Data("1".utf8)

/// The elements for `threads`, each holding `present`.
private func marks(_ threads: Set<ThreadSummary.ID>) -> [String: Data] {
    Dictionary(uniqueKeysWithValues: threads.map { ($0.syncedElement, present) })
}

/// Each change by its thread. An element that names no thread is left alone.
private func byThread(_ changes: [String: SettingChange]) -> [ThreadSummary.ID: SettingChange] {
    var byThread: [ThreadSummary.ID: SettingChange] = [:]
    for (element, change) in changes {
        guard let id = ThreadSummary.ID(syncedElement: element) else { continue }
        byThread[id] = change
    }
    return byThread
}

/// The threads pinned to the top of their lists.
struct SyncedPins: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedMailGroup.pins

    func local() throws -> LocalSettings {
        let accounts = Set(try database.accounts().map(\.id))
        return LocalSettings(
            marks(try database.pinnedThreadIDs().filter { accounts.contains($0.accountID) }),
            scope: .threads(of: accounts))
    }

    func apply(_ changes: [String: SettingChange]) throws {
        try database.setPins(byThread(changes).mapValues { $0 != .removed })
    }
}

/// Each snoozed thread, asleep or woken. A snooze ends as a removal soon after it wakes, so removals are remembered
/// for a month rather than half a year, which keeps the record small for a reader who snoozes every day.
struct SyncedSnoozes: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedMailGroup.snoozes
    let removalMemory: TimeInterval = 30 * 24 * 60 * 60

    func local() throws -> LocalSettings {
        let accounts = Set(try database.accounts().map(\.id))
        var values: [String: Data] = [:]
        for (id, state) in try database.allSnoozes() where accounts.contains(id.accountID) {
            values[id.syncedElement] = try SharedSnooze(state).encoded()
        }
        return LocalSettings(values, scope: .threads(of: accounts))
    }

    func apply(_ changes: [String: SettingChange]) throws {
        var snoozes: [ThreadSummary.ID: SnoozeState?] = [:]
        for (id, change) in byThread(changes) {
            switch change {
            case .set(let data):
                // A snooze a newer build wrote in a form this one can't read is left as it is here.
                guard let snooze = SharedSnooze.decoding(data) else { continue }
                snoozes[id] = .some(snooze.takenUp)
            case .removed:
                snoozes[id] = .some(nil)
            }
        }
        try database.takeUpSnoozes(snoozes)
    }
}

/// The threads muted on the device, in the accounts whose service has no Mute (`MailService.mutesOnDevice`). The
/// others' mutes travel with their service.
struct SyncedMutes: SettingsFamily {
    let database: MailDatabase
    let name = MailDatabase.SyncedMailGroup.mutes

    func local() throws -> LocalSettings {
        let accounts = Set(try database.accounts().filter(\.service.mutesOnDevice).map(\.id))
        return LocalSettings(
            marks(try database.deviceMutedThreadIDs().filter { accounts.contains($0.accountID) }),
            scope: .threads(of: accounts))
    }

    func apply(_ changes: [String: SettingChange]) throws {
        try database.takeUpMutes(byThread(changes).mapValues { $0 != .removed }, now: .now)
    }
}
