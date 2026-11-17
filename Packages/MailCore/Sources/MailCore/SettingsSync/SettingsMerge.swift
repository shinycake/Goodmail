public import Foundation

/// How one group's settings on this device and the shared ones come together. Each setting is merged on its own and
/// the newest change wins, wherever it was made:
/// - A setting that differs from what this device last synced was changed here, now.
/// - A setting that was synced and is gone here was removed here, now.
/// - A setting this device never synced gives way to the shared one, so a new device, or one reinstalled, takes up
///   the reader's settings instead of sharing its own untouched ones.
/// - Removals are kept for `keepingRemovals`, then forgotten.
public struct SettingsMerge: Equatable, Sendable {
    /// What changes on this device.
    public var apply: [String: SettingChange] = [:]
    /// What all devices share from now on.
    public var merged: [String: SyncedEntry] = [:]
    /// What this device has synced, to tell its next changes apart.
    public var ledger: [String: SyncedEntry] = [:]

    public init(
        local: LocalSettings, ledger synced: [String: SyncedEntry], shared: [String: SyncedEntry], now: SettingStamp,
        keepingRemovals: TimeInterval
    ) {
        let elements = Set(local.values.keys).union(synced.keys).union(shared.keys)
        for element in elements {
            guard local.scope.covers(element) else {
                // Left as the devices that hold it have it.
                merged[element] = shared[element]
                continue
            }
            let here = local.values[element]
            let mine = Self.entry(here: here, synced: synced[element], shared: shared[element], now: now)
            let winner: SyncedEntry? =
                switch (mine, shared[element]) {
                case (let mine?, let theirs?): mine.stamp > theirs.stamp ? mine : theirs
                case (let mine?, nil): mine
                case (nil, let theirs): theirs
                }
            guard let winner else { continue }
            if winner.value != here { apply[element] = winner.value.map(SettingChange.set) ?? .removed }
            merged[element] = winner
            ledger[element] = winner
        }
        let oldest = now.time.addingTimeInterval(-keepingRemovals)
        merged = merged.filter { !Self.expired($0.value, before: oldest) }
        ledger = ledger.filter { !Self.expired($0.value, before: oldest) }
    }

    /// This device's side of one setting.
    private static func entry(here: Data?, synced: SyncedEntry?, shared: SyncedEntry?, now: SettingStamp)
        -> SyncedEntry?
    {
        switch (here, synced) {
        case (let here?, nil): shared == nil ? .value(here, now) : nil
        case (let here?, .value(let data, _)?) where data == here: synced
        case (let here?, _?): .value(here, now)
        case (nil, .value?): .removed(now)
        case (nil, let synced): synced
        }
    }

    private static func expired(_ entry: SyncedEntry, before oldest: Date) -> Bool {
        if case .removed(let stamp) = entry { stamp.time < oldest } else { false }
    }
}
