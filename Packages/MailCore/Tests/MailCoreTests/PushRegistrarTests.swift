import Foundation
import Synchronization
import Testing

@testable import MailCore

struct PushRegistrarTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let device = DeviceToken(hex: "AB12", environment: .sandbox)
    private let account = AccountID.generate()
    private let margin: TimeInterval = 2 * 86_400

    private func subscription(
        token: String = "ab12", channel: PushChannel = .watch, renewedDaysAgo: Double = 1, daysLeft: Double = 5
    ) -> PushSubscription {
        PushSubscription(
            device: DeviceToken(hex: token, environment: .sandbox), channel: channel,
            renewedAt: now.addingTimeInterval(-renewedDaysAgo * 86_400),
            expiresAt: now.addingTimeInterval(daysLeft * 86_400))
    }

    private func step(_ level: NotificationLevel, _ subscription: PushSubscription?) -> PushRegistrar.Step {
        PushRegistrar.step(level: level, subscription: subscription, device: device, margin: margin, now: now)
    }

    @Test(arguments: [
        (NotificationLevel.all, PushRegistrar.Step.subscribe(renewing: nil)),
        (.primary, .subscribe(renewing: nil)),
        (.off, .none),
    ])
    func withoutASubscription(level: NotificationLevel, expected: PushRegistrar.Step) {
        #expect(step(level, nil) == expected)
    }

    @Test func aCurrentSubscriptionNeedsNothing() {
        #expect(step(.all, subscription()) == .none)
    }

    @Test func aNewTokenReplacesTheOldSubscription() {
        let old = subscription(token: "ffff")
        #expect(step(.all, old) == .replace(old))
    }

    @Test func anOldRegistrationOrALapsingSubscriptionRenewsItsChannel() {
        let graph = PushChannel.subscription(id: "s1", clientState: "secret")
        #expect(step(.all, subscription(renewedDaysAgo: 8)) == .subscribe(renewing: .watch))
        #expect(step(.all, subscription(channel: graph, daysLeft: 1)) == .subscribe(renewing: graph))
        #expect(step(.all, subscription(daysLeft: -1)) == .subscribe(renewing: .watch))
    }

    @Test func turningAlertsOffUnsubscribesTheStoredSubscription() {
        let stored = subscription(token: "ffff")
        #expect(step(.off, stored) == .unsubscribe(stored))
    }

    @Test func subscribingStoresWhatTheSourceReturned() async throws {
        let store = MemoryNotificationStore()
        let source = FakeSource(expires: now.addingTimeInterval(7 * 86_400))
        let registrar = PushRegistrar(relay: NoRelay(), store: store, now: { [now] in now })

        try await registrar.refresh(account, source: source, device: device)

        #expect(source.calls == ["subscribe ab12 renewing nil"])
        #expect(
            try store.pushSubscription(for: account)
                == PushSubscription(
                    device: device, channel: .watch, renewedAt: now, expiresAt: now.addingTimeInterval(7 * 86_400)))
    }

    @Test func renewingHandsTheSourceTheStoredChannel() async throws {
        let store = MemoryNotificationStore()
        let graph = PushChannel.subscription(id: "s1", clientState: "secret")
        try store.setPushSubscription(subscription(channel: graph, daysLeft: 1), for: account)
        let source = FakeSource(expires: now.addingTimeInterval(3 * 86_400))
        let registrar = PushRegistrar(relay: NoRelay(), store: store, now: { [now] in now })

        try await registrar.refresh(account, source: source, device: device)

        #expect(source.calls == ["subscribe ab12 renewing \(graph)"])
        #expect(try store.pushSubscription(for: account)?.renewedAt == now)
    }

    @Test func aFailedSubscribeStoresNothing() async throws {
        let store = MemoryNotificationStore()
        let registrar = PushRegistrar(relay: NoRelay(), store: store, now: { [now] in now })

        await #expect(throws: PushRelayClient.Failure.unauthorized) {
            try await registrar.refresh(account, source: FakeSource(expires: now, failing: true), device: device)
        }
        #expect(try store.pushSubscription(for: account) == nil)
    }

    @Test func aNewTokenSubscribesEvenWhenDroppingTheOldOneFails() async throws {
        let store = MemoryNotificationStore()
        try store.setPushSubscription(subscription(token: "ffff"), for: account)
        let source = FakeSource(expires: now.addingTimeInterval(86_400), failingUnsubscribe: true)
        let registrar = PushRegistrar(relay: NoRelay(), store: store, now: { [now] in now })

        try await registrar.refresh(account, source: source, device: device)

        #expect(source.calls == ["unsubscribe ffff", "subscribe ab12 renewing nil"])
        #expect(try store.pushSubscription(for: account)?.device == device)
    }

    @Test func turningAlertsOffForgetsTheSubscription() async throws {
        let store = MemoryNotificationStore()
        try store.setPushSubscription(subscription(), for: account)
        try store.setNotificationLevel(.off, for: account, now: now)
        let source = FakeSource(expires: now)
        let registrar = PushRegistrar(relay: NoRelay(), store: store, now: { [now] in now })

        try await registrar.refresh(account, source: source, device: device)

        #expect(source.calls == ["unsubscribe ab12"])
        #expect(try store.notifications(for: account, now: now).level == .off)
        #expect(try store.pushSubscription(for: account) == nil)
    }
}

/// Records what the registrar asks of it; the relay is the source's business, so the registrar's tests ignore it.
private final class FakeSource: PushSource {
    let renewalMargin: TimeInterval = 2 * 86_400
    private let expires: Date
    private let failing: Bool
    private let failingUnsubscribe: Bool
    private let recorded = Mutex<[String]>([])

    init(expires: Date, failing: Bool = false, failingUnsubscribe: Bool = false) {
        self.expires = expires
        self.failing = failing
        self.failingUnsubscribe = failingUnsubscribe
    }

    var calls: [String] { recorded.withLock { $0 } }

    func subscribe(_ device: DeviceToken, renewing channel: PushChannel?, relay: any PushRelay) async throws
        -> (channel: PushChannel, expiresAt: Date)
    {
        if failing { throw PushRelayClient.Failure.unauthorized }
        recorded.withLock { $0.append("subscribe \(device.hex) renewing \(channel.map { "\($0)" } ?? "nil")") }
        return (channel ?? .watch, expires)
    }

    func unsubscribe(_ channel: PushChannel, deviceToken: String, relay: any PushRelay) async throws {
        recorded.withLock { $0.append("unsubscribe \(deviceToken)") }
        if failingUnsubscribe { throw PushRelayClient.Failure.status(500) }
    }
}

private struct NoRelay: PushRelay {
    var graphNotificationURL: URL { URL(string: "https://relay.example.test/v1/graph")! }
    func register(_ device: DeviceToken, proof: String) async throws {}
    func unregister(deviceToken: String, proof: String) async throws {}
    func register(_ subscription: RelayGraphSubscription) async throws {}
    func unregisterGraphSubscription(id: String, clientState: String) async throws {}
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
