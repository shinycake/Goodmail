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

/// How an account's service reaches the relay for this device.
public enum PushChannel: Codable, Equatable, Sendable {
    /// Gmail: the relay knows the device by the account's address, and one Pub/Sub watch serves every device.
    case watch
    /// Outlook: this device's own Graph subscription, which the relay trusts by its `clientState`.
    case subscription(id: String, clientState: String)
}

/// A service that can tell the push relay when an account's mail changes.
public protocol PushSource: Sendable {
    /// Subscriptions are renewed once less than this is left.
    var renewalMargin: TimeInterval { get }

    /// Starts sending the account's new Inbox mail to `device` through `relay`, or renews `channel` when it is
    /// still this device's. Returns the channel and when it lapses unless renewed.
    func subscribe(_ device: DeviceToken, renewing channel: PushChannel?, relay: any PushRelay) async throws
        -> (channel: PushChannel, expiresAt: Date)

    /// Stops sending the account's mail to `deviceToken` through `channel`.
    func unsubscribe(_ channel: PushChannel, deviceToken: String, relay: any PushRelay) async throws
}

/// An Outlook device's Graph subscription, as the relay stores it.
public struct RelayGraphSubscription: Equatable, Sendable {
    public var id: String
    public var clientState: String
    public var account: AccountID
    public var device: DeviceToken
    public var expiresAt: Date

    public init(id: String, clientState: String, account: AccountID, device: DeviceToken, expiresAt: Date) {
        self.id = id
        self.clientState = clientState
        self.account = account
        self.device = device
        self.expiresAt = expiresAt
    }
}

/// The push relay (PushWorker): wakes registered devices when their accounts' mail changes.
public protocol PushRelay: Sendable {
    /// Where Graph sends Outlook's change notifications.
    var graphNotificationURL: URL { get }

    /// Gmail: registers the device for the address `proof` vouches for.
    func register(_ device: DeviceToken, proof: String) async throws
    func unregister(deviceToken: String, proof: String) async throws

    /// Outlook: stores or renews the device's Graph subscription.
    func register(_ subscription: RelayGraphSubscription) async throws
    func unregisterGraphSubscription(id: String, clientState: String) async throws
}

/// What the relay and the service know about one account's pushes to this device.
public struct PushSubscription: Equatable, Sendable {
    public var device: DeviceToken
    public var channel: PushChannel
    /// When the relay last heard from this device for the account.
    public var renewedAt: Date
    /// When the service stops notifying the relay unless the subscription is renewed.
    public var expiresAt: Date

    public init(device: DeviceToken, channel: PushChannel, renewedAt: Date, expiresAt: Date) {
        self.device = device
        self.channel = channel
        self.renewedAt = renewedAt
        self.expiresAt = expiresAt
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
