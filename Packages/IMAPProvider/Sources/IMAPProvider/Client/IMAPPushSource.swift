public import Foundation
public import MailCore

/// IMAP push: iCloud and other IMAP servers push to no one but Apple Mail, so each device registers a watch with
/// the relay, which logs in to the account's server each minute and alerts the device when new mail reaches the
/// Inbox. The watch hands the relay the login, which it keeps encrypted and uses only to read the Inbox's STATUS.
public struct IMAPPushSource: PushSource {
    /// The relay keeps a watch this long after its device last registered it.
    static let watchLifetime: TimeInterval = 30 * 86_400

    let accountID: AccountID
    let server: MailServer
    let username: String
    let password: String

    public init(accountID: AccountID, settings: MailServerSettings, password: String) {
        self.accountID = accountID
        server = settings.imap
        username = settings.username
        self.password = password
    }

    /// Registered on every refresh: the relay renews a login it already holds without logging in, and a new
    /// password, as after signing in again, reaches it at once.
    public var renewalMargin: TimeInterval { .infinity }

    /// Registers `channel` again when it is this device's watch, otherwise a new one.
    public func subscribe(_ device: DeviceToken, renewing channel: PushChannel?, relay: any PushRelay) async throws
        -> (channel: PushChannel, expiresAt: Date)
    {
        let (id, secret) =
            if case .mailboxWatch(let id, let secret) = channel { (id, secret) } else { Self.newWatch() }
        try await relay.register(
            RelayMailboxWatch(
                id: id, secret: secret, account: accountID, device: device, server: server, username: username,
                password: password))
        return (.mailboxWatch(id: id, secret: secret), Date.now.addingTimeInterval(Self.watchLifetime))
    }

    public func unsubscribe(_ channel: PushChannel, deviceToken: String, relay: any PushRelay) async throws {
        guard case .mailboxWatch(let id, let secret) = channel else { return }
        try await relay.unregisterMailboxWatch(id: id, secret: secret)
    }

    /// A lowercase UUID and 32 random bytes as hex.
    static func newWatch() -> (id: String, secret: String) {
        var generator = SystemRandomNumberGenerator()
        let secret = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }.lowercaseHex
        return (UUID().uuidString.lowercased(), secret)
    }
}
