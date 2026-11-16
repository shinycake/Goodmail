/// An IMAP device's watch on its account's Inbox, as the relay stores it. IMAP servers push nothing to anyone but
/// Apple Mail, so the relay logs in each minute and alerts when new mail arrived: it needs the server and the login,
/// which it keeps encrypted and forgets when the watch is removed (PushWorker/README.md).
public struct RelayMailboxWatch: Equatable, Sendable {
    /// A UUID the device made.
    public var id: String
    /// 32 random bytes as hex, which only the device and the relay know; it proves later renewals and removals.
    public var secret: String
    public var account: AccountID
    public var device: DeviceToken
    public var server: MailServer
    public var username: String
    public var password: String

    public init(
        id: String, secret: String, account: AccountID, device: DeviceToken, server: MailServer, username: String,
        password: String
    ) {
        self.id = id
        self.secret = secret
        self.account = account
        self.device = device
        self.server = server
        self.username = username
        self.password = password
    }
}
