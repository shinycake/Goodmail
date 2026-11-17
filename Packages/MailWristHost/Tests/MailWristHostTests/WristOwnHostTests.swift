import Foundation
import GmailProvider
import MailCore
import MailStore
import MailWrist
import Synchronization
import Testing

@testable import MailWristHost

/// The watch reads its Gmail and Outlook accounts itself once it has filled them, and leaves the rest to the iPhone.
struct WristOwnHostTests {
    private let database: MailDatabase
    private let shared = MemoryKeychain()
    private let provider: SyncingProvider
    private let gmail = WristAccount(
        id: AccountID(rawValue: "g"), address: "g@gmail.com", color: .teal, unread: 0, service: .gmail)
    private let icloud = WristAccount(
        id: AccountID(rawValue: "i"), address: "i@icloud.com", color: .orange, unread: 0, service: .icloud)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        database = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "WristOwnHostTests-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
        provider = SyncingProvider(threads: [
            ThreadSummary(
                id: ThreadSummary.ID(accountID: gmail.id, threadID: "t1"), subject: "Lunch?", snippet: "",
                sender: Contact(name: "Noa", address: "noa@x.com"), date: Self.now - 60, isUnread: true,
                messageCount: 1, labelIDs: ["INBOX"])
        ])
        try shared.set(Data("token".utf8), for: OAuthClient.gmail.refreshTokenKey(gmail.id))
    }

    private func host() -> WristOwnHost {
        WristOwnHost(
            database: database, signIns: WristSignIns(device: MemoryKeychain(), shared: shared),
            provider: { [provider] _ in provider },
            uploads: FileManager.default.temporaryDirectory.appending(path: "Uploads-\(UUID().uuidString)"),
            now: { Self.now })
    }

    /// The threads of the watch's own Inbox snapshot.
    private func storedThreads() async throws -> [String] {
        var snapshots = host().snapshots().makeAsyncIterator()
        return try #require(try await snapshots.next()).rows.map(\.id.threadID)
    }

    @Test func aNewAccountIsFilledBeforeItTurnsDirect() async throws {
        let host = host()
        try await host.follow([gmail, icloud], independence: .on)
        #expect(try await host.sources() == [gmail.id: .relayed(.filling), icloud.id: .relayed(.service)])

        try await host.sync()

        #expect(try await host.sources() == [gmail.id: .direct, icloud.id: .relayed(.service)])
        #expect(try await storedThreads() == ["t1"])
    }

    @Test func aRejectedSignInGoesBackToTheIPhone() async throws {
        let host = host()
        try await host.follow([gmail], independence: .on)
        try await host.sync()
        provider.fail(with: OAuthClient.Failure.tokenEndpoint(status: 400, error: "invalid_grant"))

        try await host.sync()

        #expect(try await host.sources() == [gmail.id: .relayed(.signInRejected)])
    }

    @Test func anAccountTheIPhoneRemovedIsDroppedWithItsMail() async throws {
        let host = host()
        try await host.follow([gmail], independence: .on)
        try await host.sync()

        try await host.follow([], independence: .on)

        #expect(try await storedThreads().isEmpty)
        #expect(try database.accounts().isEmpty)
        #expect(try await host.sources().isEmpty)
        #expect(try shared.data(for: OAuthClient.gmail.refreshTokenKey(gmail.id)) != nil, "the iPhone's copy stays")
    }

    @Test func theSwitchOffLeavesEveryAccountToTheIPhone() async throws {
        let host = host()
        try await host.follow([gmail, icloud], independence: .on)
        try await host.sync()

        try await host.follow([gmail, icloud], independence: .off)
        try await host.sync()

        #expect(try await host.sources() == [gmail.id: .relayed(.switchedOff), icloud.id: .relayed(.service)])
    }

    @Test func nothingSyncsWhileSwitchedOff() async throws {
        let host = host()
        try await host.follow([gmail], independence: .off)

        try await host.sync()

        #expect(try await storedThreads().isEmpty)
        #expect(provider.changeRequests == 0)
    }

    @Test func aSecondCatchUpJoinsTheOneRunning() async throws {
        let host = host()
        try await host.follow([gmail], independence: .on)
        try await host.sync()
        let before = provider.changeRequests
        let open = provider.holdChanges()

        async let first: Void = host.catchUp()
        while provider.changeRequests == before { await Task.yield() }
        async let second: Void = host.catchUp()
        try await Task.sleep(for: .milliseconds(100))
        open.finish()
        _ = await (first, second)

        #expect(provider.changeRequests == before + 1)
    }

    @Test func aCancelledCatchUpKeepsWhatWasStoredAndTheAccountsHealth() async throws {
        let host = host()
        try await host.follow([gmail], independence: .on)
        try await host.sync()
        let before = provider.changeRequests
        let open = provider.holdChanges()

        let refresh = Task { await host.catchUp() }
        while provider.changeRequests == before { await Task.yield() }
        refresh.cancel()
        await refresh.value
        open.finish()

        #expect(try await host.sources() == [gmail.id: .direct])
        #expect(try await storedThreads() == ["t1"])
        await host.catchUp()
        #expect(provider.changeRequests == before + 2, "the next catch-up runs afresh")
    }
}

final class MemoryKeychain: SecretStore {
    private let items = Mutex<[String: Data]>([:])

    func data(for key: String) throws -> Data? { items.withLock { $0[key] } }
    func set(_ data: Data, for key: String) throws { items.withLock { $0[key] = data } }
    func remove(_ key: String) throws { _ = items.withLock { $0.removeValue(forKey: key) } }
}
