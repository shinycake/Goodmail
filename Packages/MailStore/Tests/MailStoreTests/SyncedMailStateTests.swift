import Foundation
import MailCore
import Testing

@testable import MailStore

/// An iPhone and a Mac sharing pins, snoozes and device mutes through one shared store (ADR-037): what one device
/// does shows on the other, a snooze wakes once, and taking a change up never queues it for the service again.
struct SyncedMailStateTests {
    private let phone: MailDatabase
    private let mac: MailDatabase
    private let cloud = SharedMemory()
    private let phoneLedger = SharedLedger()
    private let macLedger = SharedLedger()
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .teal, service: .gmail)
    private let outlook = Account(
        id: AccountID(rawValue: "o"), email: "me@outlook.com", color: .blue, service: .outlook)
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let wake = start.addingTimeInterval(3 * 3600)

    init() throws {
        phone = try Self.database()
        mac = try Self.database()
        for database in [phone, mac] {
            try database.save(gmail)
            try database.save(outlook)
            try database.upsert([thread("t1", in: gmail), thread("t2", in: gmail), thread("t1", in: outlook)])
        }
    }

    private static func database() throws -> MailDatabase {
        try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "SyncedMailState-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
    }

    private func thread(
        _ threadID: String, in account: Account, date: Date = start.addingTimeInterval(-3600)
    ) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: threadID), subject: "Subject \(threadID)",
            snippet: "", sender: Contact(name: nil, address: "dana@example.com"), date: date, isUnread: false,
            messageCount: 1, labelIDs: [SystemLabel.inbox])
    }

    private func id(_ threadID: String, in account: Account? = nil) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: (account ?? gmail).id, threadID: threadID)
    }

    /// One pass of the device's mail-state sync at `date`.
    @discardableResult
    private func sync(_ database: MailDatabase, at date: Date) async throws -> SettingsSyncPass {
        let ledger = database === phone ? phoneLedger : macLedger
        return try await SettingsSync(
            cloud: cloud, ledger: ledger, families: OffMainDatabase(database).syncedMailState, now: { date }
        ).sync()
    }

    private func commands(_ database: MailDatabase, at date: Date) -> MailCommands {
        MailCommands(store: database, replay: { _ in }, now: { date })
    }

    private func inbox(_ database: MailDatabase) async throws -> Set<String> {
        var threads = database.threads(in: Mailbox(labelID: SystemLabel.inbox, accountID: gmail.id), window: .whole)
            .makeAsyncIterator()
        return Set(try await threads.next()?.threads.map(\.id.threadID) ?? [])
    }

    private func queued(_ database: MailDatabase, for account: Account? = nil) throws -> [ThreadAction] {
        try database.pendingIntents(for: (account ?? gmail).id).map(\.action)
    }

    @Test func aPinOnOneDeviceShowsOnTheOtherAndAnUnpinTakesItAway() async throws {
        try await commands(phone, at: Self.start).pin([id("t1")], true)
        try await sync(phone, at: Self.start)
        let pass = try await sync(mac, at: Self.start.addingTimeInterval(1))
        #expect(pass.changed == [MailDatabase.SyncedMailGroup.pins])
        #expect(try mac.pinnedThreadIDs() == [id("t1")])

        try await commands(mac, at: Self.start).pin([id("t1")], false)
        try await sync(mac, at: Self.start.addingTimeInterval(2))
        try await sync(phone, at: Self.start.addingTimeInterval(3))
        #expect(try phone.pinnedThreadIDs().isEmpty)
        #expect(try queued(phone).isEmpty && queued(mac).isEmpty, "a pin is the devices' alone")
    }

    @Test func aSnoozeTakenUpLeavesTheInboxThereWithoutQueuingAnything() async throws {
        try await commands(mac, at: Self.start).snooze([id("t1")], until: Self.wake)
        try await sync(mac, at: Self.start)
        try await sync(phone, at: Self.start.addingTimeInterval(1))

        #expect(try phone.snoozes(of: [id("t1")]) == [id("t1"): .asleep(until: Self.wake, keeper: .otherDevice)])
        #expect(try await inbox(phone) == ["t2"])
        #expect(try queued(phone).isEmpty, "the Mac archived it at the service already")
        #expect(try await sync(phone, at: Self.start.addingTimeInterval(2)).changed.isEmpty, "taken up as it was")
        #expect(try await sync(mac, at: Self.start.addingTimeInterval(2)).changed.isEmpty)
        // The phone's own pass before its sync hears of the archive doesn't end the snooze.
        try await commands(phone, at: Self.start.addingTimeInterval(2)).wakeSnoozed()
        #expect(try phone.snoozes(of: [id("t1")]).count == 1)
        var snoozed = phone.snoozedThreads().makeAsyncIterator()
        #expect(try await snoozed.next()?.map(\.keeper) == [.otherDevice], "only the Mac alerts")
    }

    @Test func theKeeperWakesTheThreadAndTheOtherDeviceOnlyTakesThatUp() async throws {
        try await commands(mac, at: Self.start).snooze([id("t1")], until: Self.wake)
        try await sync(mac, at: Self.start)
        try await sync(phone, at: Self.start.addingTimeInterval(1))
        #expect(try phone.nextWakeDate() == Self.wake.addingTimeInterval(SnoozeKeeper.fallbackDelay))
        #expect(try await commands(phone, at: Self.wake).wakeSnoozed().isEmpty, "the phone waits for the Mac")

        #expect(try await commands(mac, at: Self.wake).wakeSnoozed() == [id("t1")])
        try await sync(mac, at: Self.wake.addingTimeInterval(1))
        try await sync(phone, at: Self.wake.addingTimeInterval(2))

        #expect(try phone.snoozes(of: [id("t1")]) == [id("t1"): .woke(at: Self.wake)])
        #expect(try await commands(phone, at: Self.wake.addingTimeInterval(3600)).wakeSnoozed().isEmpty)
        #expect(try queued(phone).isEmpty, "the thread went back to the Inbox once, from the Mac")
    }

    @Test func anotherDeviceWakesTheThreadWhenTheKeeperIsAway() async throws {
        try await commands(mac, at: Self.start).snooze([id("t1")], until: Self.wake)
        try await sync(mac, at: Self.start)
        try await sync(phone, at: Self.start.addingTimeInterval(1))
        let late = Self.wake.addingTimeInterval(SnoozeKeeper.fallbackDelay)

        #expect(try await commands(phone, at: late).wakeSnoozed() == [id("t1")])
        #expect(try queued(phone) == [.modifyLabels(add: [SystemLabel.inbox, SystemLabel.unread], remove: [])])
        try await sync(phone, at: late.addingTimeInterval(1))
        // The Mac comes back from sleep: its round takes up the wake before it would wake the thread itself.
        try await sync(mac, at: late.addingTimeInterval(3600))
        #expect(try await commands(mac, at: late.addingTimeInterval(3600)).wakeSnoozed().isEmpty)
        #expect(try mac.snoozes(of: [id("t1")]) == [id("t1"): .woke(at: late)])
        #expect(try queued(mac) == [.archive], "only the snooze's own archive")
    }

    @Test func unsnoozingOnOneDeviceEndsTheSnoozeOnTheOther() async throws {
        try await commands(mac, at: Self.start).snooze([id("t1")], until: Self.wake)
        try await sync(mac, at: Self.start)
        try await sync(phone, at: Self.start.addingTimeInterval(1))
        try await commands(phone, at: Self.start.addingTimeInterval(2)).unsnooze([id("t1")])
        try await sync(phone, at: Self.start.addingTimeInterval(3))
        try await sync(mac, at: Self.start.addingTimeInterval(4))

        #expect(try mac.snoozes(of: [id("t1")]).isEmpty)
        #expect(try await commands(mac, at: Self.wake).wakeSnoozed().isEmpty)
    }

    @Test func snoozingAgainOnTheOtherDeviceMakesItTheKeeper() async throws {
        try await commands(mac, at: Self.start).snooze([id("t1")], until: Self.wake)
        try await sync(mac, at: Self.start)
        try await sync(phone, at: Self.start.addingTimeInterval(1))
        let later = Self.wake.addingTimeInterval(3600)
        try await commands(phone, at: Self.start.addingTimeInterval(2)).snooze([id("t1")], until: later)
        try await sync(phone, at: Self.start.addingTimeInterval(3))
        try await sync(mac, at: Self.start.addingTimeInterval(4))

        #expect(try phone.snoozes(of: [id("t1")]) == [id("t1"): .asleep(until: later, keeper: .thisDevice)])
        #expect(try mac.snoozes(of: [id("t1")]) == [id("t1"): .asleep(until: later, keeper: .otherDevice)])
    }

    @Test func aMuteReachesTheOtherDeviceSoARepliesStayOutAndDontAlert() async throws {
        let muted = id("t1", in: outlook)
        try await commands(mac, at: Self.start).perform(.mute, on: [muted])
        try await sync(mac, at: Self.start)
        try await sync(phone, at: Self.start.addingTimeInterval(1))

        #expect(try phone.deviceMutedThreadIDs() == [muted])
        #expect(try phone.thread(muted)?.labelIDs.contains(SystemLabel.muted) == true)
        #expect(try queued(phone, for: outlook).isEmpty)
        let reply = thread("t1", in: outlook, date: Self.start.addingTimeInterval(60))
        try phone.apply(StoreChanges(accountID: outlook.id, upserts: [reply], fetchedAt: Self.start))
        #expect(try phone.claimAlerts(among: [reply], in: outlook, now: Self.start).isEmpty)
        #expect(try phone.thread(muted)?.labelIDs.contains(SystemLabel.inbox) == false)
    }

    @Test func anUnmuteReachesTheOtherDevice() async throws {
        let muted = id("t1", in: outlook)
        try await commands(mac, at: Self.start).perform(.mute, on: [muted])
        try await sync(mac, at: Self.start)
        try await sync(phone, at: Self.start.addingTimeInterval(1))
        try await commands(phone, at: Self.start).perform(.unmute, on: [muted])
        try await sync(phone, at: Self.start.addingTimeInterval(2))
        try await sync(mac, at: Self.start.addingTimeInterval(3))

        #expect(try mac.deviceMutedThreadIDs().isEmpty)
        #expect(try mac.thread(muted)?.labelIDs.contains(SystemLabel.muted) == false)
    }

    @Test func gmailMutesTravelWithGmail() async throws {
        try await commands(mac, at: Self.start).perform(.mute, on: [id("t1")])
        try await sync(mac, at: Self.start)
        #expect(cloud.data(for: SettingsSync.cloudKey(MailDatabase.SyncedMailGroup.mutes)) == nil, "nothing to share")
    }
}
