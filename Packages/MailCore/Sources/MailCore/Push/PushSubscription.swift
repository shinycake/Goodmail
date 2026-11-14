import Foundation

/// The APNs server a device token belongs to: development builds get sandbox tokens, TestFlight and App Store
/// builds production ones.
public enum APNsEnvironment: String, Codable, Sendable {
    case sandbox, production
}

/// This device's APNs address.
public struct DeviceToken: Equatable, Sendable {
    /// The token as lowercase hex, as the relay takes it.
    public let hex: String
    public let environment: APNsEnvironment

    public init(_ data: Data, environment: APNsEnvironment) {
        hex = data.map { String(format: "%02x", $0) }.joined()
        self.environment = environment
    }

    public init(hex: String, environment: APNsEnvironment) {
        self.hex = hex.lowercased()
        self.environment = environment
    }
}

/// A service that can tell the push relay when an account's mail changes.
public protocol PushSource: Sendable {
    /// Asks the service to notify the relay of the account's Inbox changes, renewing any earlier request. Returns
    /// when the request lapses unless renewed.
    func watch() async throws -> Date

    /// Proof of the account's address that the relay checks before it stores this device for it.
    func relayProof() async throws -> String
}

/// The push relay (PushWorker): wakes registered devices when their accounts' mail changes.
public protocol PushRelay: Sendable {
    func register(_ device: DeviceToken, proof: String) async throws
    func unregister(deviceToken: String, proof: String) async throws
}

/// What the relay and the service know about one account's pushes to this device.
public struct PushSubscription: Equatable, Sendable {
    /// The device token the relay holds for the account.
    public var deviceToken: String
    public var registeredAt: Date
    /// When the service stops notifying the relay unless the watch is renewed.
    public var watchExpiresAt: Date

    public init(deviceToken: String, registeredAt: Date, watchExpiresAt: Date) {
        self.deviceToken = deviceToken
        self.registeredAt = registeredAt
        self.watchExpiresAt = watchExpiresAt
    }
}

/// Where each account's alert choice and push subscription are kept. `MailStore` implements it, so the app and the
/// notification extension share them.
public protocol NotificationStore: Sendable {
    /// The account's choice and progress; `AccountNotifications.initial(at: now)` when it has none yet.
    func notifications(for account: AccountID, now: Date) throws -> AccountNotifications
    func setNotificationLevel(_ level: NotificationLevel, for account: AccountID, now: Date) throws
    /// Moves `seenThrough` forward to `date`, never back, so two processes that alert never undo each other.
    func markSeen(through date: Date, for account: AccountID, now: Date) throws
    func pushSubscription(for account: AccountID) throws -> PushSubscription?
    /// `nil` forgets it, as after unregistering.
    func setPushSubscription(_ subscription: PushSubscription?, for account: AccountID) throws
}
