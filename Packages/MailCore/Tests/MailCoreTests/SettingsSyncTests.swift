import Foundation
import Synchronization
import Testing

@testable import MailCore

struct SettingsSyncTests {
    /// Two devices sharing one cloud, each with its own settings and ledger, and a clock the test moves.
    private final class Devices: Sendable {
        let cloud = MemoryCloud()
        let clock = TestClock()
        let phone = MemoryFamily()
        let pad = MemoryFamily()
        let phoneSync: SettingsSync
        let padSync: SettingsSync

        init() {
            let clock = clock
            let now: @Sendable () -> Date = { clock.now }
            phoneSync = SettingsSync(cloud: cloud, ledger: MemoryLedger(), families: [phone], now: now)
            padSync = SettingsSync(cloud: cloud, ledger: MemoryLedger(), families: [pad], now: now)
        }

        func tick() { clock.tick() }
    }

    @Test func aNewDeviceTakesUpTheSettingsTheOtherShared() async throws {
        let devices = Devices()
        devices.phone.values.withLock { $0 = ["layout": Data("chat".utf8)] }
        devices.pad.values.withLock { $0 = ["layout": Data("classic".utf8)] }
        try await devices.phoneSync.sync()
        devices.tick()
        let pass = try await devices.padSync.sync()
        #expect(pass.changed == ["prefs"])
        #expect(devices.pad.values.withLock { $0 } == ["layout": Data("chat".utf8)])
    }

    @Test func anEditOnOneDeviceReachesTheOther() async throws {
        let devices = Devices()
        try await devices.phoneSync.sync()
        try await devices.padSync.sync()
        devices.tick()
        devices.pad.values.withLock { $0["undo"] = Data("20".utf8) }
        try await devices.padSync.sync()
        devices.tick()
        let pass = try await devices.phoneSync.sync()
        #expect(pass.changed == ["prefs"])
        #expect(devices.phone.values.withLock { $0 } == ["undo": Data("20".utf8)])
        // Nothing changed since, so another pass changes nothing.
        devices.tick()
        #expect(try await devices.phoneSync.sync().changed.isEmpty)
    }

    @Test func concurrentEditsSettleOnTheNewestOnBothDevices() async throws {
        let devices = Devices()
        devices.phone.values.withLock { $0 = ["undo": Data("10".utf8)] }
        try await devices.phoneSync.sync()
        try await devices.padSync.sync()
        devices.tick()
        devices.phone.values.withLock { $0["undo"] = Data("5".utf8) }
        devices.pad.values.withLock { $0["undo"] = Data("30".utf8) }
        // The pad's edit is seen later, so it's the newer one.
        try await devices.phoneSync.sync()
        devices.tick()
        try await devices.padSync.sync()
        try await devices.phoneSync.sync()
        #expect(devices.phone.values.withLock { $0 } == ["undo": Data("30".utf8)])
        #expect(devices.pad.values.withLock { $0 } == ["undo": Data("30".utf8)])
    }

    @Test func aRecordFromANewerBuildIsLeftAlone() async throws {
        let devices = Devices()
        let newer = Data(#"{"format":2,"entries":{}}"#.utf8)
        devices.cloud.set(newer, for: SettingsSync.cloudKey("prefs"))
        devices.phone.values.withLock { $0 = ["undo": Data("10".utf8)] }
        try await devices.phoneSync.sync()
        #expect(devices.cloud.data(for: SettingsSync.cloudKey("prefs")) == newer)
    }

    @Test func aFailingGroupDoesNotStopThePass() async throws {
        let cloud = MemoryCloud()
        cloud.set(Data("not json".utf8), for: SettingsSync.cloudKey("broken"))
        let good = MemoryFamily()
        good.values.withLock { $0 = ["undo": Data("10".utf8)] }
        let sync = SettingsSync(
            cloud: cloud, ledger: MemoryLedger(), families: [MemoryFamily(name: "broken"), good])
        let pass = try await sync.sync()
        #expect(pass.failures.map(\.family) == ["broken"])
        #expect(cloud.data(for: SettingsSync.cloudKey("prefs")) != nil)
    }

    @Test func theLedgerOutlivesTheSyncSoARelaunchKnowsWhatItSynced() async throws {
        let cloud = MemoryCloud()
        let ledger = MemoryLedger()
        let family = MemoryFamily()
        family.values.withLock { $0 = ["rule": Data("a".utf8)] }
        try await SettingsSync(cloud: cloud, ledger: ledger, families: [family]).sync()
        family.values.withLock { $0 = [:] }
        // A new sync, as after a relaunch, still sees the rule as removed here rather than never synced.
        try await SettingsSync(cloud: cloud, ledger: ledger, families: [family]).sync()
        let shared = try #require(try SharedFamily.decode(cloud.data(for: SettingsSync.cloudKey("prefs"))))
        #expect(shared.entries["rule"]?.value == nil)
    }
}

final class MemoryCloud: SecretStore {
    private let store = Mutex<[String: Data]>([:])
    func data(for key: String) -> Data? { store.withLock { $0[key] } }
    func set(_ data: Data, for key: String) { store.withLock { $0[key] = data } }
    func remove(_ key: String) { store.withLock { $0[key] = nil } }
}

final class TestClock: Sendable {
    private let seconds = Mutex<TimeInterval>(0)
    var now: Date { Date(timeIntervalSinceReferenceDate: seconds.withLock { $0 }) }
    func tick() { seconds.withLock { $0 += 1 } }
}

final class MemoryLedger: SettingsLedgerStore {
    private let ledger = Mutex<SettingsLedger?>(nil)
    func load() throws -> SettingsLedger? { ledger.withLock { $0 } }
    func save(_ ledger: SettingsLedger) throws { self.ledger.withLock { $0 = ledger } }
}

final class MemoryFamily: SettingsFamily {
    let name: String
    let values = Mutex<[String: Data]>([:])

    init(name: String = "prefs") {
        self.name = name
    }

    func local() throws -> LocalSettings { LocalSettings(values.withLock { $0 }) }

    func apply(_ changes: [String: SettingChange]) throws {
        values.withLock { values in
            for (key, change) in changes {
                switch change {
                case .set(let data): values[key] = data
                case .removed: values[key] = nil
                }
            }
        }
    }
}
