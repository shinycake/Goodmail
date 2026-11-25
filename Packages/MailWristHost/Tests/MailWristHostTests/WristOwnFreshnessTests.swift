import Foundation
import GmailProvider
import MailCore
import MailStore
import MailWrist
import Synchronization
import Testing

@testable import MailWristHost

/// The watch says how fresh the mail it reads itself is: when a check last worked, that one is running, or why
/// checks fail.
struct WristOwnFreshnessTests {
    private let database: MailDatabase
    private let shared = MemoryKeychain()
    private let provider = SyncingProvider(threads: [])
    private let gmail = WristAccount(
        id: AccountID(rawValue: "g"), address: "g@gmail.com", color: .teal, unread: 0, service: .gmail)
    private let icloud = WristAccount(
        id: AccountID(rawValue: "i"), address: "i@icloud.com", color: .orange, unread: 0, service: .icloud)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        database = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "WristOwnFreshnessTests-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
        try shared.set(Data("token".utf8), for: OAuthClient.gmail.refreshTokenKey(gmail.id))
    }

    private func host(now: @escaping @Sendable () -> Date = { Self.now }) async -> WristOwnHost {
        await WristOwnHost(
            database: database, signIns: WristSignIns(device: MemoryKeychain(), shared: shared),
            provider: { [provider] _ in provider },
            uploads: FileManager.default.temporaryDirectory.appending(path: "Uploads-\(UUID().uuidString)"),
            now: now, independence: .on, handBack: { _ in })
    }

    @Test func aWatchThatReadsNoAccountItselfSaysNothing() async throws {
        let host = await host()
        try await host.follow([icloud], independence: .on)

        try await host.sync()

        #expect(await host.freshness() == nil)
    }

    @Test func aCheckThatWorkedSaysWhen() async throws {
        let host = await host()
        try await host.follow([gmail], independence: .on)

        try await host.sync()

        #expect(await host.checking == .idle(lastChecked: Self.now))
        #expect(await host.freshness() == .current(checkedAt: Self.now))
    }

    @Test func aRunningCheckSaysSoAndWhenTheLastWorked() async throws {
        let host = await host()
        try await host.follow([gmail], independence: .on)
        try await host.sync()
        let before = provider.changeRequests
        let open = provider.holdChanges()

        async let refresh: Void = host.catchUp()
        while provider.changeRequests == before { await Task.yield() }

        #expect(await host.checking == .running(runs: 1, lastChecked: Self.now))
        #expect(await host.freshness() == .checking(lastChecked: Self.now))
        open.finish()
        await refresh
        #expect(await host.checking == .idle(lastChecked: Self.now))
    }

    @Test func aRejectedSignInSaysWhyAndKeepsTheLastWorkingCheck() async throws {
        let host = await host()
        try await host.follow([gmail], independence: .on)
        try await host.sync()
        provider.fail(with: OAuthClient.Failure.tokenEndpoint(status: 400, error: "invalid_grant"))

        try await host.sync()

        #expect(await host.freshness() == .behind(.signInFailed, lastChecked: Self.now))
    }

    /// Off, the footer goes; on again, it doesn't say when a check worked before the switch was off.
    @Test func theSwitchOffClearsTheFooterAndItsLastCheck() async throws {
        let clock = TestClock(Self.now)
        let host = await host(now: { clock.now() })
        try await host.follow([gmail], independence: .on)
        try await host.sync()
        #expect(await host.freshness() == .current(checkedAt: Self.now))

        try await host.follow([gmail], independence: .off)
        #expect(await host.freshness() == nil, "the iPhone reads every account now")
        try await host.sync()
        #expect(await host.freshness() == nil)

        clock.advance(by: 3_600)
        try await host.follow([gmail], independence: .on)
        let open = provider.holdChanges()
        async let checking: Void = host.sync()
        while provider.changeRequests < 2 { await Task.yield() }
        #expect(await host.freshness() == .checking(lastChecked: nil))
        open.finish()
        try await checking
        #expect(await host.freshness() == .current(checkedAt: Self.now + 3_600))
    }

    @Test func eachChangeIsSentToWhoeverShowsIt() async throws {
        let host = await host()
        var updates = host.freshnessUpdates.makeAsyncIterator()
        try await host.follow([gmail], independence: .on)

        try await host.sync()

        #expect(await updates.next() == .some(.checking(lastChecked: nil)))
        #expect(await updates.next() == .some(.current(checkedAt: Self.now)))
    }

    /// A check at launch and a background catch-up can overlap: the footer says checking until both are done.
    @Test func overlappingChecksRunUntilTheLastEnds() throws {
        var independence = WristOwnHost.Independence.on(WristOwnHost.Stretch(readying: .asLeft, start: Task {}))
        let stretch = try #require(independence.stretch).id
        let (first, second) = (UUID(), UUID())
        for check in [first, second] { independence.track(Task { [:] }, as: check, in: stretch) }

        independence.finishCheck(first, in: stretch, workedAt: Self.now)
        #expect(independence.stretch?.checks.count == 1)
        #expect(independence.stretch?.lastChecked == Self.now)
        independence.finishCheck(second, in: stretch, workedAt: nil)
        #expect(independence.stretch?.checks.isEmpty == true)
        #expect(independence.stretch?.lastChecked == Self.now, "A check that failed after one worked keeps the date")
    }
}

/// A clock the test moves.
final class TestClock: Sendable {
    private let date: Mutex<Date>

    init(_ date: Date) {
        self.date = Mutex(date)
    }

    func now() -> Date { date.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        date.withLock { $0 += interval }
    }
}
