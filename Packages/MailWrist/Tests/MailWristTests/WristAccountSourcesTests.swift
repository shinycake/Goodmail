import Foundation
import MailCore
import Testing

@testable import MailWrist

/// The watch reads an account itself only when it can and may (ADR-023); every other account stays the iPhone's.
struct WristAccountSourcesTests {
    private let id = AccountID(rawValue: "a1")
    private let current = SyncState.current(cursor: "42")

    private func account(_ service: MailService?) -> WristAccount {
        WristAccount(id: id, address: "me@example.com", color: .blue, unread: 0, service: service)
    }

    private func source(
        _ service: MailService?, signedIn: Bool = true, health: AccountHealth = .healthy, sync: SyncState? = nil,
        independence: WristIndependence = .on
    ) -> WristAccountSource? {
        WristAccountSources.resolve(
            accounts: [account(service)], signIns: signedIn ? [id] : [], health: [id: health],
            syncStates: sync.map { [id: $0] } ?? [:], independence: independence)[id]
    }

    @Test(arguments: [MailService.gmail, .outlook])
    func aSignedInCurrentHTTPSAccountIsDirect(service: MailService) {
        #expect(source(service, sync: current) == .direct)
    }

    @Test(arguments: [MailService.icloud, .imap, nil])
    func anAccountTheWatchCantReachStaysRelayed(service: MailService?) {
        #expect(source(service, sync: current) == .relayed(.service))
        #expect(source(service, sync: current, independence: .off) == .relayed(.service), "the service says more")
    }

    @Test func theSwitchTurnsEveryAccountBackToTheIPhone() {
        #expect(source(.gmail, sync: current, independence: .off) == .relayed(.switchedOff))
    }

    @Test func aSignInThatHasntArrivedWaits() {
        #expect(source(.outlook, signedIn: false, sync: current) == .relayed(.noSignIn))
    }

    @Test func aTurnedDownSignInGoesBackToTheIPhone() {
        #expect(source(.gmail, health: .needsSignIn, sync: current) == .relayed(.signInRejected))
    }

    @Test func otherSyncTroubleKeepsTheAccountDirect() {
        let failing = AccountHealth.failing(.offline)
        #expect(source(.gmail, health: failing, sync: current) == .direct)
    }

    @Test func theIPhoneServesTheAccountUntilTheWatchHasItsFirstCopy() {
        #expect(source(.gmail) == .relayed(.filling))
        let resync = SyncState.resyncing(Resync(cursor: "1", startedAt: .now, generation: 1))
        #expect(source(.gmail, sync: resync) == .relayed(.filling))
    }

    @Test func everyAccountGetsASource() {
        let other = AccountID(rawValue: "a2")
        let sources = WristAccountSources.resolve(
            accounts: [
                account(.gmail),
                WristAccount(id: other, address: "me@icloud.com", color: .teal, unread: 0, service: .icloud),
            ],
            signIns: [id], health: [:], syncStates: [id: current], independence: .on)
        #expect(sources == [id: .direct, other: .relayed(.service)])
    }

    /// A stored snapshot that lists an account twice is read again at every launch, so it must not trap.
    @Test func anAccountListedTwiceGetsOneSource() {
        let sources = WristAccountSources.resolve(
            accounts: [account(.gmail), account(.gmail)], signIns: [id], health: [:], syncStates: [id: current],
            independence: .on)
        #expect(sources == [id: .direct])
    }
}

/// The watch runs what it can for an account it reads itself; the iPhone runs the rest.
struct WristExecutorTests {
    static let watchKinds: [WristCommand.Kind] = [
        .archive, .moveToInbox, .trash, .untrash, .markRead(true), .reply("Thanks!"),
    ]
    static let phoneKinds: [WristCommand.Kind] = [.pin(true), .snooze(until: .distantFuture), .unsnooze]

    @Test(arguments: watchKinds)
    func aDirectAccountsMailChangesOnTheWatch(kind: WristCommand.Kind) {
        #expect(WristExecutor.for(kind: kind, source: .direct) == .watch)
        #expect(WristExecutor.for(kind: kind, source: .relayed(.noSignIn)) == .phone)
    }

    @Test(arguments: phoneKinds)
    func pinsAndSnoozesAlwaysRunOnTheIPhone(kind: WristCommand.Kind) {
        #expect(WristExecutor.for(kind: kind, source: .direct) == .phone)
    }

    @Test func aCommandFromAnOlderWatchRunsOnTheIPhone() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":{"archive":{}},"madeAt":0,"threads":[]}"#
        #expect(try JSONDecoder().decode(WristCommand.self, from: Data(json.utf8)).executor == .phone)
    }

    @Test func theWatchsOwnCommandSaysSo() throws {
        let command = WristCommand(threads: [], kind: .archive, madeAt: .now, executor: .watch)
        let decoded = try JSONDecoder().decode(WristCommand.self, from: try JSONEncoder().encode(command))
        #expect(decoded == command)
    }

    @Test func anAccountFromAnOlderIPhoneHasNoService() throws {
        let json = #"{"id":"a1","address":"me@example.com","color":"blue","unread":0}"#
        #expect(try JSONDecoder().decode(WristAccount.self, from: Data(json.utf8)).service == nil)
    }
}
