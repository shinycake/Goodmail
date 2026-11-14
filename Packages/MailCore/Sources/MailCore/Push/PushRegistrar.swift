import Foundation

/// Keeps each account's push subscription in step with its alert choice and this device's token: subscribes, renews
/// before the service lets the subscription lapse, and unsubscribes when alerts are off.
public actor PushRegistrar {
    /// Subscriptions are renewed at least this often, so the relay keeps a device whose earlier registration it lost.
    public static let registrationAge: TimeInterval = 7 * 86_400

    /// The one thing an account's subscription needs now.
    public enum Step: Equatable, Sendable {
        /// Subscribe, renewing the stored channel when there is one.
        case subscribe(renewing: PushChannel?)
        /// The stored subscription belongs to an old device token: drop it and subscribe this one.
        case replace(PushSubscription)
        case unsubscribe(PushSubscription)
        case none
    }

    private let relay: any PushRelay
    private let store: any NotificationStore
    private let now: @Sendable () -> Date

    public init(relay: any PushRelay, store: any NotificationStore, now: @escaping @Sendable () -> Date = { .now }) {
        self.relay = relay
        self.store = store
        self.now = now
    }

    /// What `subscription` needs at `level`, for `device`, renewing once less than `margin` is left.
    public static func step(
        level: NotificationLevel, subscription: PushSubscription?, device: DeviceToken, margin: TimeInterval,
        now: Date
    ) -> Step {
        guard level != .off else { return subscription.map(Step.unsubscribe) ?? .none }
        guard let subscription else { return .subscribe(renewing: nil) }
        guard subscription.device == device else { return .replace(subscription) }
        let due =
            now.timeIntervalSince(subscription.renewedAt) >= registrationAge
            || subscription.expiresAt.timeIntervalSince(now) < margin
        return due ? .subscribe(renewing: subscription.channel) : .none
    }

    /// Brings one account's subscription up to date. Throws what the relay or the service threw; what was done
    /// before is kept, and the next call takes it from there.
    public func refresh(_ account: AccountID, source: any PushSource, device: DeviceToken) async throws {
        let at = now()
        let level = try store.notifications(for: account, now: at).level
        let stored = try store.pushSubscription(for: account)
        switch Self.step(level: level, subscription: stored, device: device, margin: source.renewalMargin, now: at) {
        case .subscribe(let channel):
            try await subscribe(account, source: source, device: device, renewing: channel, at: at)
        case .replace(let old):
            // Best effort: the old token's subscription lapses on its own, and alerts on this one matter more.
            try? await source.unsubscribe(old.channel, deviceToken: old.device.hex, relay: relay)
            try await subscribe(account, source: source, device: device, renewing: nil, at: at)
        case .unsubscribe(let old):
            try await unsubscribe(account, old, source: source)
        case .none:
            break
        }
    }

    /// Takes this device off the relay for an account about to be removed.
    public func unsubscribe(_ account: AccountID, source: any PushSource) async throws {
        guard let stored = try store.pushSubscription(for: account) else { return }
        try await unsubscribe(account, stored, source: source)
    }

    private func subscribe(
        _ account: AccountID, source: any PushSource, device: DeviceToken, renewing channel: PushChannel?, at: Date
    ) async throws {
        let (channel, expiresAt) = try await source.subscribe(device, renewing: channel, relay: relay)
        try store.setPushSubscription(
            PushSubscription(device: device, channel: channel, renewedAt: at, expiresAt: expiresAt), for: account)
    }

    private func unsubscribe(_ account: AccountID, _ subscription: PushSubscription, source: any PushSource)
        async throws
    {
        try await source.unsubscribe(subscription.channel, deviceToken: subscription.device.hex, relay: relay)
        try store.setPushSubscription(nil, for: account)
    }
}
