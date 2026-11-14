import Foundation
import Synchronization
import Testing

@testable import MailCore

struct PushRegistrarTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let device = DeviceToken(hex: "AB12", environment: .sandbox)
    private let account = AccountID.generate()

    private func subscription(token: String = "ab12", registeredDaysAgo: Double = 1, watchDaysLeft: Double = 5)
        -> PushSubscription
    {
        PushSubscription(
            deviceToken: token, registeredAt: now.addingTimeInterval(-registeredDaysAgo * 86_400),
            watchExpiresAt: now.addingTimeInterval(watchDaysLeft * 86_400))
    }

    @Test(arguments: [
        (NotificationLevel.all, nil as PushSubscription?, PushRegistrar.Step.subscribe),
        (.primary, nil, .subscribe),
        (.off, nil, .none),
    ])
    func withoutASubscription(level: NotificationLevel, subscription: PushSubscription?, step: PushRegistrar.Step) {
        #expect(PushRegistrar.step(level: level, subscription: subscription, device: device, now: now) == step)
    }

    @Test func aCurrentSubscriptionNeedsNothing() {
        #expect(PushRegistrar.step(level: .all, subscription: subscription(), device: device, now: now) == .none)
    }

    @Test func aNewTokenOrAnOldRegistrationRegistersAgain() {
        let newToken = subscription(token: "ffff")
        let old = subscription(registeredDaysAgo: 8)
        #expect(PushRegistrar.step(level: .all, subscription: newToken, device: device, now: now) == .subscribe)
        #expect(PushRegistrar.step(level: .all, subscription: old, device: device, now: now) == .subscribe)
    }

    @Test func aWatchAboutToLapseIsRenewed() {
        let lapsing = subscription(watchDaysLeft: 1)
        #expect(PushRegistrar.step(level: .all, subscription: lapsing, device: device, now: now) == .renewWatch)
    }

    @Test func turningAlertsOffUnregistersTheStoredToken() {
        let stored = subscription(token: "ffff")
        #expect(
            PushRegistrar.step(level: .off, subscription: stored, device: device, now: now)
                == .unsubscribe(deviceToken: "ffff"))
    }

    @Test func subscribingRegistersThenWatchesAndStoresBoth() async throws {
        let store = MemoryNotificationStore()
        let relay = RecordingRelay()
        let registrar = PushRegistrar(relay: relay, store: store, now: { [now] in now })
        let source = FakeSource(expires: now.addingTimeInterval(7 * 86_400))

        try await registrar.refresh(account, source: source, device: device)

        #expect(relay.calls == ["register ab12 proof"])
        #expect(
            try store.pushSubscription(for: account)
                == PushSubscription(
                    deviceToken: "ab12", registeredAt: now, watchExpiresAt: now.addingTimeInterval(7 * 86_400)))
    }

    @Test func aFailedRegistrationStoresNothing() async throws {
        let store = MemoryNotificationStore()
        let relay = RecordingRelay(failing: true)
        let registrar = PushRegistrar(relay: relay, store: store, now: { [now] in now })

        await #expect(throws: PushRelayClient.Failure.unauthorized) {
            try await registrar.refresh(account, source: FakeSource(expires: now), device: device)
        }
        #expect(try store.pushSubscription(for: account) == nil)
    }

    @Test func turningAlertsOffForgetsTheSubscription() async throws {
        let store = MemoryNotificationStore()
        try store.setPushSubscription(subscription(), for: account)
        try store.setNotificationLevel(.off, for: account, now: now)
        let relay = RecordingRelay()
        let registrar = PushRegistrar(relay: relay, store: store, now: { [now] in now })

        try await registrar.refresh(account, source: FakeSource(expires: now), device: device)

        #expect(relay.calls == ["unregister ab12 proof"])
        #expect(try store.notifications(for: account, now: now).level == .off)
        #expect(try store.pushSubscription(for: account) == nil)
    }
}

private struct FakeSource: PushSource {
    let expires: Date
    func watch() async throws -> Date { expires }
    func relayProof() async throws -> String { "proof" }
}

private final class RecordingRelay: PushRelay {
    private let recorded = Mutex<[String]>([])
    private let failing: Bool

    init(failing: Bool = false) {
        self.failing = failing
    }

    var calls: [String] { recorded.withLock { $0 } }

    func register(_ device: DeviceToken, proof: String) async throws {
        if failing { throw PushRelayClient.Failure.unauthorized }
        recorded.withLock { $0.append("register \(device.hex) \(proof)") }
    }

    func unregister(deviceToken: String, proof: String) async throws {
        recorded.withLock { $0.append("unregister \(deviceToken) \(proof)") }
    }
}

final class MemoryNotificationStore: NotificationStore {
    private let notifications = Mutex<[AccountID: AccountNotifications]>([:])
    private let subscriptions = Mutex<[AccountID: PushSubscription]>([:])

    func notifications(for account: AccountID, now: Date) throws -> AccountNotifications {
        notifications.withLock { $0[account] } ?? .initial(at: now)
    }

    func setNotificationLevel(_ level: NotificationLevel, for account: AccountID, now: Date) throws {
        notifications.withLock { $0[account, default: .initial(at: now)].level = level }
    }

    func markSeen(through date: Date, for account: AccountID, now: Date) throws {
        notifications.withLock { stored in
            var current = stored[account] ?? .initial(at: now)
            current.seenThrough = max(current.seenThrough, date)
            stored[account] = current
        }
    }

    func pushSubscription(for account: AccountID) throws -> PushSubscription? {
        subscriptions.withLock { $0[account] }
    }

    func setPushSubscription(_ subscription: PushSubscription?, for account: AccountID) throws {
        subscriptions.withLock { $0[account] = subscription }
    }
}
