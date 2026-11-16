import Foundation
import MailCore
import Synchronization
import Testing

struct AccountSharingTests {
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .blue, service: .gmail)
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "me@icloud.com", color: .green, service: .icloud)
    private let outlook = Account(
        id: AccountID(rawValue: "o"), email: "me@outlook.com", color: .orange, service: .outlook)

    private func sharing(shared: MemoryDirectory, device: MemoryDirectory) -> AccountSharing {
        AccountSharing(shared: shared, device: device) { id, service in "\(service.rawValue).\(id.rawValue)" }
    }

    @Test func anotherDevicesAccountIsMissingOnceItsSignInArrives() async throws {
        let shared = MemoryDirectory()
        let phone = sharing(shared: shared, device: MemoryDirectory(["gmail.g": "token", "outlook.o": "token"]))
        try await phone.share([outlook, gmail])
        let pad = sharing(shared: shared, device: MemoryDirectory())

        let plan = try await pad.plan(for: [])

        #expect(plan.missing == [outlook, gmail], "in the order the phone keeps them")
    }

    @Test func anAccountWhoseSignInHasntArrivedIsntMissingYet() async throws {
        let shared = MemoryDirectory()
        try await sharing(shared: shared, device: MemoryDirectory(["gmail.g": "token"])).share([gmail])
        try shared.remove("gmail.g")

        let plan = try await sharing(shared: shared, device: MemoryDirectory()).plan(for: [])

        #expect(plan.missing.isEmpty)
    }

    @Test func anAccountRemovedElsewhereIsSaidSoAndAMissingRecordRemovesNothing() async throws {
        let shared = MemoryDirectory()
        let phone = sharing(shared: shared, device: MemoryDirectory(["gmail.g": "t", "icloud.i": "p"]))
        try await phone.share([gmail, icloud])
        try await phone.retire(gmail.id)

        let plan = try await phone.plan(for: [gmail, icloud, outlook])

        #expect(plan.removedElsewhere == [gmail.id], "never shared, Outlook stays")
    }

    @Test func sharingAgainDoesntBringBackARemovedAccount() async throws {
        let shared = MemoryDirectory()
        let phone = sharing(shared: shared, device: MemoryDirectory(["gmail.g": "t"]))
        try await phone.share([gmail])
        try await phone.retire(gmail.id)

        try await phone.share([gmail])

        #expect(try await phone.plan(for: [gmail]).removedElsewhere == [gmail.id])
    }

    @Test func aRenameOrNewColorElsewhereIsTakenUp() async throws {
        let shared = MemoryDirectory()
        let phone = sharing(shared: shared, device: MemoryDirectory(["gmail.g": "t"]))
        var renamed = gmail
        renamed.name = "Dana Levi"
        renamed.color = .custom(RGBColor(red: 51, green: 102, blue: 255))
        try await phone.share([renamed])

        let plan = try await sharing(shared: shared, device: MemoryDirectory()).plan(for: [gmail])

        #expect(plan.changedElsewhere == [renamed])
        #expect(plan.missing.isEmpty)
    }

    @Test func sharingCopiesTheDevicesSignInButKeepsANewerSharedOne() async throws {
        let shared = MemoryDirectory(["icloud.i": "newer"])
        let device = MemoryDirectory(["gmail.g": "token", "icloud.i": "older"])

        try await sharing(shared: shared, device: device).share([gmail, icloud])

        #expect(try shared.string("gmail.g") == "token")
        #expect(try shared.string("icloud.i") == "newer")
    }

    @Test func theOrderPutsSharedAccountsByPlaceAndThisDevicesOwnAfter() async throws {
        let shared = MemoryDirectory()
        try await sharing(shared: shared, device: MemoryDirectory(["gmail.g": "t", "outlook.o": "t"]))
            .share([outlook, gmail])
        let plan = try await sharing(shared: shared, device: MemoryDirectory()).plan(for: [icloud, gmail])

        #expect(plan.order(of: [icloud, gmail] + plan.missing) == [outlook.id, gmail.id, icloud.id])
    }

    @Test func aDeviceWithFewerAccountsKeepsTheSharedPlacesInsteadOfRenumbering() async throws {
        let shared = MemoryDirectory()
        let tokens = ["gmail.g": "t", "icloud.i": "p", "outlook.o": "t"]
        let phone = sharing(shared: shared, device: MemoryDirectory(tokens))
        let pad = sharing(shared: shared, device: MemoryDirectory(tokens))
        try await phone.share([gmail, icloud, outlook])
        let written = shared.writes

        // The pad has no iCloud; its Outlook is still third, after the phone's iCloud.
        try await pad.share([gmail, outlook])
        try await phone.share([gmail, icloud, outlook])

        #expect(shared.writes == written, "neither device rewrites the other's places, round after round")
    }

    @Test func aReorderOnADeviceWithFewerAccountsKeepsTheOthersNextToTheirNeighbors() async throws {
        let shared = MemoryDirectory()
        let tokens = ["gmail.g": "t", "icloud.i": "p", "outlook.o": "t"]
        try await sharing(shared: shared, device: MemoryDirectory(tokens)).share([gmail, icloud, outlook])
        let pad = sharing(shared: shared, device: MemoryDirectory(tokens))

        try await pad.share([outlook, gmail])

        let plan = try await pad.plan(for: [gmail, icloud, outlook])
        #expect(plan.order(of: [gmail, icloud, outlook]) == [outlook.id, gmail.id, icloud.id])
    }

    @Test func signInsPreferTheSharedCopyAndKeepItOnTheDevice() throws {
        let device = MemoryDirectory(["k": "old"])
        let secrets = SharedSecrets(device: device, shared: MemoryDirectory(["k": "rotated"]))

        #expect(try secrets.data(for: "k") == Data("rotated".utf8))
        #expect(try device.string("k") == "rotated", "still there if sharing stops")
    }

    @Test func aSignInOnlyTheDeviceHasIsntShared() throws {
        let shared = MemoryDirectory()
        let secrets = SharedSecrets(device: MemoryDirectory(["k": "mine"]), shared: shared)

        #expect(try secrets.data(for: "k") == Data("mine".utf8))
        #expect(try shared.string("k") == nil, "another device may have removed its account")
    }

    @Test func signInsAreWrittenAndRemovedInBothPlaces() throws {
        let device = MemoryDirectory()
        let shared = MemoryDirectory()
        let secrets = SharedSecrets(device: device, shared: shared)

        try secrets.set(Data("t".utf8), for: "k")
        #expect(try device.string("k") == "t")
        #expect(try shared.string("k") == "t")

        try secrets.remove("k")
        #expect(try device.string("k") == nil)
        #expect(try shared.string("k") == nil)
    }
}

/// A Keychain in memory.
final class MemoryDirectory: SecretDirectory {
    private let items: Mutex<[String: Data]>
    private let written = Mutex(0)

    init(_ strings: [String: String] = [:]) {
        items = Mutex(strings.mapValues { Data($0.utf8) })
    }

    func data(for key: String) throws -> Data? { items.withLock { $0[key] } }
    func set(_ data: Data, for key: String) throws {
        items.withLock { $0[key] = data }
        written.withLock { $0 += 1 }
    }

    /// How many times anything was written, so a test can tell nothing was.
    var writes: Int { written.withLock { $0 } }
    func remove(_ key: String) throws { _ = items.withLock { $0.removeValue(forKey: key) } }
    func keys() throws -> [String] { items.withLock { Array($0.keys) } }

    func string(_ key: String) throws -> String? { try data(for: key).map { String(decoding: $0, as: UTF8.self) } }
}
