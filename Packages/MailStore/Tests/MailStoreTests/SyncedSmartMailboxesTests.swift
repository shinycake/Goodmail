import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// Smart mailboxes and VIPs following the reader across devices through the settings sync.
struct SyncedSmartMailboxesTests {
    private let cloud = SharedMemory()

    private static func database() throws -> MailDatabase {
        try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "SyncedSmart-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
    }

    private func sync(_ database: MailDatabase, ledger: SharedLedger) async throws {
        let pass = try await SettingsSync(
            cloud: cloud, ledger: ledger, families: OffMainDatabase(database).syncedSettings
        ).sync()
        #expect(pass.failures.isEmpty)
    }

    @Test func anEditReplacesTheBoxOnEveryDeviceInsteadOfAddingOne() async throws {
        let (phone, pad) = (try Self.database(), try Self.database())
        let (phoneLedger, padLedger) = (SharedLedger(), SharedLedger())
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)

        var box = SmartMailbox(
            name: .custom("Dana"), symbol: "person", filter: .condition(.text(.sender, .contains("dana"))))
        try phone.saveSmartMailbox(box)
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)
        #expect(try pad.smartMailboxes().last == box)

        box.name = .custom("Dana Levi")
        try pad.saveSmartMailbox(box)
        try await sync(pad, ledger: padLedger)
        try await sync(phone, ledger: phoneLedger)
        #expect(try phone.smartMailboxes() == pad.smartMailboxes())
        #expect(try phone.smartMailboxes().map(\.name) == [.unread, .vips, .withAttachments, .custom("Dana Levi")])
    }

    @Test func aStartingBoxDeletedOnOneDeviceStaysDeletedOnANewOne() async throws {
        let phone = try Self.database()
        let phoneLedger = SharedLedger()
        try await sync(phone, ledger: phoneLedger)
        try phone.deleteSmartMailbox(SmartMailbox.ID(rawValue: "vips"))
        try await sync(phone, ledger: phoneLedger)

        // A new device starts with the whole set, and takes up the reader's choice instead of sharing it again.
        let newPad = try Self.database()
        try await sync(newPad, ledger: SharedLedger())
        #expect(try newPad.smartMailboxes().map(\.id.rawValue) == ["unread", "attachments"])
        try await sync(phone, ledger: phoneLedger)
        #expect(try phone.smartMailboxes().map(\.id.rawValue) == ["unread", "attachments"])
    }

    @Test func vipsAddedOnTwoDevicesBothStay() async throws {
        let (phone, pad) = (try Self.database(), try Self.database())
        let (phoneLedger, padLedger) = (SharedLedger(), SharedLedger())
        let dana = try #require(SenderAddress("dana@example.com"))
        let noa = try #require(SenderAddress("noa@example.com"))
        try phone.setVIP(dana, true)
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)
        try pad.setVIP(noa, true)
        try phone.setVIP(dana, false)
        try await sync(pad, ledger: padLedger)
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)
        #expect(try phone.vips().senders == [noa])
        #expect(try pad.vips().senders == [noa])
    }

    @Test func aBoxThisBuildCantReadStillTravels() async throws {
        let (phone, pad) = (try Self.database(), try Self.database())
        let (phoneLedger, padLedger) = (SharedLedger(), SharedLedger())
        try phone.write { db in
            try db.execute(
                sql: "INSERT INTO smartMailbox (id, position, json) VALUES ('later', 9, '{\"from\":\"a later build\"}')"
            )
        }
        try await sync(phone, ledger: phoneLedger)
        try await sync(pad, ledger: padLedger)
        try await sync(phone, ledger: phoneLedger)
        let stored = try pad.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM smartMailbox ORDER BY position")
        }
        #expect(stored == ["unread", "vips", "attachments", "later"])
        #expect(try pad.smartMailboxes() == SmartMailbox.startingSet, "left out where it can't be read")
        let kept = try phone.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM smartMailbox") }
        #expect(kept == 4)
    }
}
