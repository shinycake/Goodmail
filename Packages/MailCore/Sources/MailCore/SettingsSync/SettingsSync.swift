public import Foundation

/// Keeps the reader's settings the same on all their devices: each pass merges every group on this device with the
/// shared copy (`SettingsMerge`), takes up what other devices changed, and shares the result. The shared copies live
/// in iCloud Keychain in the app, one item per group. Passes run one at a time, since nothing in a pass suspends,
/// and off the main actor, since the Keychain, the defaults and the database all block.
public actor SettingsSync {
    private let cloud: any SecretStore
    private let ledgerStore: any SettingsLedgerStore
    private let families: [any SettingsFamily]
    private let now: @Sendable () -> Date
    private var ledger: SettingsLedger?

    /// How long a removal is remembered unless its group says otherwise (`SettingsFamily.removalMemory`).
    public static let removalMemory: TimeInterval = 180 * 24 * 60 * 60

    public init(
        cloud: any SecretStore, ledger: any SettingsLedgerStore, families: [any SettingsFamily],
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.cloud = cloud
        ledgerStore = ledger
        self.families = families
        self.now = now
    }

    /// One pass over every group. A group that fails is left for the next pass; the others still sync.
    @discardableResult
    public func sync() throws -> SettingsSyncPass {
        var ledger = try ledger ?? ledgerStore.load() ?? SettingsLedger()
        let stamp = SettingStamp(time: now(), device: ledger.device)
        var pass = SettingsSyncPass()
        for family in families {
            do {
                let key = Self.cloudKey(family.name)
                // A record a newer build wrote in a form this one can't read is left alone.
                guard let shared = try SharedFamily.decode(try cloud.data(for: key)) else { continue }
                let merge = SettingsMerge(
                    local: try family.local(), ledger: ledger.families[family.name] ?? [:], shared: shared.entries,
                    now: stamp, keepingRemovals: family.removalMemory)
                if !merge.apply.isEmpty {
                    try family.apply(merge.apply)
                    pass.changed.insert(family.name)
                }
                if merge.merged != shared.entries {
                    try cloud.set(try SharedFamily(entries: merge.merged).encoded(), for: key)
                }
                ledger.families[family.name] = merge.ledger
            } catch {
                pass.failures.append(SettingsSyncPass.Failure(family: family.name, error: error))
            }
        }
        if ledger != self.ledger {
            try ledgerStore.save(ledger)
            self.ledger = ledger
        }
        return pass
    }

    public static func cloudKey(_ family: String) -> String { "settings." + family }
}

/// A group as the cloud holds it.
struct SharedFamily: Codable, Equatable {
    /// Bumped when the form changes in a way older builds can't read.
    static let currentFormat = 1

    var format = currentFormat
    var entries: [String: SyncedEntry]

    /// The record in `data`; an empty one when there is none yet, and `nil` when a newer build wrote it.
    static func decode(_ data: Data?) throws -> SharedFamily? {
        guard let data else { return SharedFamily(entries: [:]) }
        let family = try JSONDecoder().decode(SharedFamily.self, from: data)
        return family.format > currentFormat ? nil : family
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }
}

/// What one pass did.
public struct SettingsSyncPass: Sendable {
    /// The groups that changed on this device, by name.
    public var changed: Set<String> = []
    public var failures: [Failure] = []

    public struct Failure: Sendable {
        public var family: String
        public var error: any Error
    }
}
