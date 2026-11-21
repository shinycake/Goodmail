import Foundation
import Synchronization
import Testing

@testable import MailCore

/// Pins, snoozes and device mutes travel between the reader's devices as `SettingsSync` groups (ADR-037): each
/// thread is an element named by its account and thread, and a snooze knows which device answers for its wake.
struct MailStateSyncTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test(arguments: ["t1", "AAQkADAw/Zm9v+YmFy==", "a/b/c"])
    func aThreadsElementNamesItsAccountAndThread(threadID: String) throws {
        let id = ThreadSummary.ID(accountID: AccountID(rawValue: "6F1C-ACCOUNT"), threadID: threadID)
        #expect(id.syncedElement == "6F1C-ACCOUNT/\(threadID)")
        #expect(ThreadSummary.ID(syncedElement: id.syncedElement) == id)
    }

    @Test(arguments: ["no-separator", "/t1", "a1/"])
    func anElementWithoutBothPartsNamesNoThread(element: String) {
        #expect(ThreadSummary.ID(syncedElement: element) == nil)
    }

    @Test func aScopeOfAccountsCoversOnlyTheirThreads() {
        let scope = LocalSettings.Scope.threads(of: [AccountID(rawValue: "a1")])
        #expect(scope.covers("a1/t1"))
        #expect(!scope.covers("a2/t1"))
        #expect(!scope.covers("a1"))
    }

    @Test func theDeviceThatSnoozedAThreadWakesItOnTimeAndAlerts() {
        let keeper = SnoozeKeeper.thisDevice
        #expect(keeper.wakeTime(for: Self.start) == Self.start)
        #expect(keeper.alerts)
    }

    @Test func anotherDeviceWakesItOnlyAfterTheFallbackDelayAndSilently() {
        let keeper = SnoozeKeeper.otherDevice
        #expect(keeper.wakeTime(for: Self.start) == Self.start.addingTimeInterval(SnoozeKeeper.fallbackDelay))
        #expect(!keeper.alerts)
    }

    @Test(arguments: [
        SharedSnooze.asleep(until: start), SharedSnooze.woke(at: start.addingTimeInterval(90)),
    ])
    func aSharedSnoozeReadsBackAsItWasWritten(snooze: SharedSnooze) throws {
        let data = try snooze.encoded()
        #expect(try SharedSnooze(data) == snooze)
        #expect(try snooze.encoded() == data, "the same snooze always reads the same, so it isn't shared again")
    }

    @Test func aSnoozeIsSharedWithoutItsKeeper() {
        #expect(SharedSnooze(.asleep(until: Self.start, keeper: .thisDevice)) == .asleep(until: Self.start))
        #expect(SharedSnooze(.asleep(until: Self.start, keeper: .otherDevice)) == .asleep(until: Self.start))
        #expect(SharedSnooze(.woke(at: Self.start)) == .woke(at: Self.start))
    }

    @Test func aSnoozeTakenUpFromAnotherDeviceIsKeptThere() {
        #expect(SharedSnooze.asleep(until: Self.start).takenUp == .asleep(until: Self.start, keeper: .otherDevice))
        #expect(SharedSnooze.woke(at: Self.start).takenUp == .woke(at: Self.start))
    }

    @Test func aSnoozeFromANewerBuildReadsAsNothing() {
        #expect(SharedSnooze.decoding(Data(#"{"dreaming":{}}"#.utf8)) == nil)
    }

    @Test func eachGroupForgetsItsRemovalsAfterItsOwnTime() async throws {
        let cloud = MemoryCloud()
        let clock = TestClock()
        let brief = MemoryFamily(name: "snoozes", removalMemory: 10)
        let lasting = MemoryFamily(name: "pins")
        for family in [brief, lasting] { family.values.withLock { $0 = ["a1/t1": Data("1".utf8)] } }
        let sync = SettingsSync(
            cloud: cloud, ledger: MemoryLedger(), families: [brief, lasting], now: { clock.now })
        try await sync.sync()
        clock.tick()
        for family in [brief, lasting] { family.values.withLock { $0 = [:] } }
        try await sync.sync()
        for _ in 0..<11 { clock.tick() }
        try await sync.sync()

        let snoozes = try #require(try SharedFamily.decode(cloud.data(for: SettingsSync.cloudKey("snoozes"))))
        let pins = try #require(try SharedFamily.decode(cloud.data(for: SettingsSync.cloudKey("pins"))))
        #expect(snoozes.entries.isEmpty)
        #expect(pins.entries["a1/t1"]?.value == nil)
        #expect(pins.entries["a1/t1"] != nil, "an unpin is still remembered")
    }
}
