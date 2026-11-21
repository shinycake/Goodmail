public import Foundation

/// The APNs server a device token belongs to: development builds get sandbox tokens, TestFlight and App Store
/// builds production ones.
public enum APNsEnvironment: String, Codable, Sendable {
    case sandbox, production
}

extension APNsEnvironment {
    /// Development-signed builds carry a provisioning profile with `aps-environment` set to development, and get
    /// sandbox tokens. TestFlight and App Store builds carry no profile and get production ones.
    public init(provisioningProfile profile: String?) {
        let development = #/<key>aps-environment</key>\s*<string>development</string>/#
        self = profile?.contains(development) == true ? .sandbox : .production
    }

    /// Reads the profile of the app at `bundle`: `embedded.mobileprovision` on iPhone and iPad, and
    /// `Contents/embedded.provisionprofile` in a Mac app, where the first isn't.
    public init(bundleAt bundle: URL) {
        let profile = ["embedded.mobileprovision", "Contents/embedded.provisionprofile"].lazy
            .compactMap { try? String(contentsOf: bundle.appending(path: $0), encoding: .isoLatin1) }
            .first
        self.init(provisioningProfile: profile)
    }
}

/// This device's APNs address, with its paired watch's when the watch app has one (ADR-023).
public struct DeviceToken: Equatable, Sendable {
    /// The token as lowercase hex, as the relay takes it.
    public let hex: String
    public let environment: APNsEnvironment
    /// The paired watch's token as lowercase hex, in the same environment. The relay alerts the watch with it when
    /// the iPhone doesn't confirm an alert in time; the watch never registers itself. Anything the relay would refuse
    /// as a token is left out, so a bad one never costs the iPhone its own alerts.
    public let watch: String?

    public init(_ data: Data, environment: APNsEnvironment, watch: String? = nil) {
        self.init(hex: data.lowercaseHex, environment: environment, watch: watch)
    }

    public init(hex: String, environment: APNsEnvironment, watch: String? = nil) {
        self.hex = hex.lowercased()
        self.environment = environment
        self.watch = watch.map { $0.lowercased() }.flatMap { Self.isToken($0) ? $0 : nil }
    }

    /// What the relay takes as an APNs token: 32 to 100 bytes as hex.
    static func isToken(_ hex: String) -> Bool {
        (64...200).contains(hex.count) && hex.allSatisfy(\.isHexDigit)
    }

    /// The same iPhone token, with `watch` as its companion.
    public func pairing(_ watch: String?) -> DeviceToken {
        DeviceToken(hex: hex, environment: environment, watch: watch)
    }

    /// Whether `other` is this iPhone's own token, whatever watch either names.
    func isSamePhone(as other: DeviceToken) -> Bool {
        hex == other.hex && environment == other.environment
    }
}

/// How an account's service reaches the relay for this device.
public enum PushChannel: Codable, Equatable, Sendable {
    /// Gmail: the relay knows the device by the account's address, and one Pub/Sub watch serves every device.
    case watch
    /// Outlook: this device's own Graph subscription, which the relay trusts by its `clientState`.
    case subscription(id: String, clientState: String)
    /// iCloud and other IMAP accounts: this device's own watch, which the relay looks at the Inbox for and trusts
    /// by its `secret`.
    case mailboxWatch(id: String, secret: String)
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

    /// Gives `relay` what it needs to read the account's new mail, since it alerts only with a real email's sender
    /// and subject, at `level`. Runs on every refresh while alerts are on, with the subscription as stored, so a
    /// new sign-in reaches the relay at once.
    func shareMailbox(with relay: any PushRelay, channel: PushChannel, level: NotificationLevel) async throws
}

extension PushSource {
    /// A service whose subscription already hands the relay its way in, as an IMAP watch does, shares nothing more.
    public func shareMailbox(with relay: any PushRelay, channel: PushChannel, level: NotificationLevel) async throws {}
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
    /// Gmail: hands the relay the account's refresh token, so it can read the mail a notification announces, and
    /// whether the account alerts for its Primary category only. The relay finds the account from the token itself.
    func shareMailbox(refreshToken: String, primaryOnly: Bool) async throws

    /// Outlook: stores or renews the device's Graph subscription.
    func register(_ subscription: RelayGraphSubscription) async throws
    func unregisterGraphSubscription(id: String, clientState: String) async throws
    /// Outlook: hands the relay the account's refresh token, so it can read the mail Graph notifies about. The
    /// subscription's clientState proves the device made it.
    func shareGraphMailbox(subscriptionID: String, clientState: String, refreshToken: String) async throws

    /// IMAP: stores or renews the device's watch on the account's Inbox, which hands the relay the login.
    func register(_ watch: RelayMailboxWatch) async throws
    func unregisterMailboxWatch(id: String, secret: String) async throws

    /// Confirms that this iPhone received the alert with `id`, so the relay doesn't send it to the watch as well.
    func acknowledge(alert id: String) async throws
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
