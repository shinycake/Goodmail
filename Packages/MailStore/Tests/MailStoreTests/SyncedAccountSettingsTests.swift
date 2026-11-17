import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailStore

/// Two devices' databases syncing their settings through one shared store.
struct SyncedAccountSettingsTests {
    private let phone: MailDatabase
    private let pad: MailDatabase
    private let cloud = SharedMemory()
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .teal, service: .gmail)
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "me@icloud.com", color: .blue, service: .icloud)

    init() throws {
        phone = try Self.database()
        pad = try Self.database()
        for database in [phone, pad] {
            try database.save(gmail)
            try database.save(icloud)
        }
    }

    private static func database() throws -> MailDatabase {
        try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "SyncedSettings-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
    }

    @discardableResult
    private func sync(_ database: MailDatabase, ledger: SharedLedger) async throws -> SettingsSyncPass {
        try await SettingsSync(cloud: cloud, ledger: ledger, families: database.syncedSettings).sync()
    }

    @Test func settingsMadeOnOneDeviceReachTheOther() async throws {
        let (phoneLedger, padLedger) = (SharedLedger(), SharedLedger())
        try phone.apply(StoreChanges(accountID: icloud.id, signature: "Sent from my phone"))
        try phone.setNotificationLevel(.off, for: icloud.id, now: .now)
        try phone.setBadgeSource(.primary, for: gmail.id)
        let rule = MailRule(name: "Star all", condition: .all([]), actions: [.star])
        try phone.setRules([rule])
        try await sync(phone, ledger: phoneLedger)

        let pass = try await sync(pad, ledger: padLedger)
        #expect(pass.failures.isEmpty)
        #expect(pass.changed == ["signatures", "alerts", "badges", "rules"])
        #expect(try pad.signature(for: icloud.id) == "Sent from my phone")
        #expect(try pad.notifications(for: icloud.id, now: .now).level == .off)
        #expect(try pad.badgeSources()[gmail.id] == .primary)
        #expect(try pad.rules() == [rule])
    }

    @Test func gmailSignaturesAreLeftToGmail() async throws {
        try phone.apply(StoreChanges(accountID: gmail.id, signature: "From Gmail"))
        try await sync(phone, ledger: SharedLedger())
        try await sync(pad, ledger: SharedLedger())
        #expect(try pad.signature(for: gmail.id) == nil)
    }

    @Test func rulesAddedOnBothDevicesBothStayInTheirOrder() async throws {
        let (phoneLedger, padLedger) = (SharedLedger(), SharedLedger())
        let first = MailRule(name: "First", condition: .all([]), actions: [.star])
        try phone.setRules([first])
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)

        let fromPhone = MailRule(name: "From phone", condition: .all([]), actions: [.pin])
        let fromPad = MailRule(name: "From pad", condition: .all([]), actions: [.markRead])
        try phone.setRules([first, fromPhone])
        try pad.setRules([first, fromPad])
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)
        try await sync(phone, ledger: phoneLedger)

        for database in [phone, pad] {
            let names = try database.rules().map(\.name)
            #expect(names.first == "First")
            #expect(Set(names) == ["First", "From phone", "From pad"])
        }
        #expect(try phone.rules() == pad.rules())
    }

    @Test func aRuleRemovedOnOneDeviceLeavesTheOther() async throws {
        let (phoneLedger, padLedger) = (SharedLedger(), SharedLedger())
        try phone.setRules([MailRule(name: "Gone", condition: .all([]), actions: [.star])])
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)
        try pad.setRules([])
        try await sync(pad, ledger: padLedger)
        try await sync(phone, ledger: phoneLedger)
        #expect(try phone.rules().isEmpty)
    }

    @Test func anAccountOnlyOneDeviceHasKeepsItsSettingsForTheDevicesThatHaveIt() async throws {
        let (phoneLedger, padLedger) = (SharedLedger(), SharedLedger())
        let outlook = Account(id: AccountID(rawValue: "o"), email: "me@outlook.com", color: .orange, service: .outlook)
        try phone.save(outlook)
        try phone.apply(StoreChanges(accountID: outlook.id, signature: "Work"))
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)
        // The pad adds the account later and takes up its signature then.
        try pad.save(outlook)
        try await sync(pad, ledger: padLedger)
        #expect(try pad.signature(for: outlook.id) == "Work")
    }
}

final class SharedMemory: SecretStore {
    private let items = Mutex<[String: Data]>([:])
    func data(for key: String) -> Data? { items.withLock { $0[key] } }
    func set(_ data: Data, for key: String) { items.withLock { $0[key] = data } }
    func remove(_ key: String) { items.withLock { $0[key] = nil } }
}

final class SharedLedger: SettingsLedgerStore {
    private let ledger = Mutex<SettingsLedger?>(nil)
    func load() -> SettingsLedger? { ledger.withLock { $0 } }
    func save(_ ledger: SettingsLedger) { self.ledger.withLock { $0 = ledger } }
}
