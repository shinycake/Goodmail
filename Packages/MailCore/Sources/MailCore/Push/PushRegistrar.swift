import Foundation

/// Keeps each account's push subscription in step with its alert choice and this device's token: registers the
/// device with the relay, renews the service's watch before it lapses, and unregisters when alerts are off.
///
/// The service's watch is shared by every device on the account, so it is renewed but never stopped.
public actor PushRegistrar {
    /// Registrations are repeated this often, so the relay keeps a device whose earlier registration it lost.
    public static let registrationAge: TimeInterval = 7 * 86_400
    /// Watches are renewed once less than this is left. Gmail's last seven days.
    public static let watchMargin: TimeInterval = 2 * 86_400

    /// The one thing an account's subscription needs now.
    public enum Step: Equatable, Sendable {
        /// Register the device and start the watch.
        case subscribe
        /// Renew the watch only.
        case renewWatch
        /// Remove this device token from the relay.
        case unsubscribe(deviceToken: String)
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

    /// What `subscription` needs at `level`, for `device`.
    public static func step(
        level: NotificationLevel, subscription: PushSubscription?, device: DeviceToken, now: Date
    ) -> Step {
        guard level != .off else {
            return subscription.map { .unsubscribe(deviceToken: $0.deviceToken) } ?? .none
        }
        guard let subscription, subscription.deviceToken == device.hex,
            now.timeIntervalSince(subscription.registeredAt) < registrationAge
        else { return .subscribe }
        return subscription.watchExpiresAt.timeIntervalSince(now) < watchMargin ? .renewWatch : .none
    }

    /// Brings one account's subscription up to date. Throws what the relay or the service threw; what was done
    /// before is kept, and the next call takes it from there.
    public func refresh(_ account: AccountID, source: any PushSource, device: DeviceToken) async throws {
        let at = now()
        let notifications = try store.notifications(for: account, now: at)
        let subscription = try store.pushSubscription(for: account)
        switch Self.step(level: notifications.level, subscription: subscription, device: device, now: at) {
        case .subscribe:
            try await relay.register(device, proof: try await source.relayProof())
            let expires = try await source.watch()
            try store.setPushSubscription(
                PushSubscription(deviceToken: device.hex, registeredAt: at, watchExpiresAt: expires), for: account)
        case .renewWatch:
            guard var subscription else { return }
            subscription.watchExpiresAt = try await source.watch()
            try store.setPushSubscription(subscription, for: account)
        case .unsubscribe(let token):
            try await relay.unregister(deviceToken: token, proof: try await source.relayProof())
            try store.setPushSubscription(nil, for: account)
        case .none:
            break
        }
    }

    /// Takes this device off the relay for an account about to be removed. The watch stays for other devices.
    public func unsubscribe(_ account: AccountID, source: any PushSource) async throws {
        guard let subscription = try store.pushSubscription(for: account) else { return }
        try await relay.unregister(deviceToken: subscription.deviceToken, proof: try await source.relayProof())
        try store.setPushSubscription(nil, for: account)
    }
}
