/// What a service keeps on the addresses an account sends as, read on each sync: the signature added to new mail,
/// and the account's other addresses (aliases) mail can go from. Gmail keeps both on its send-as addresses. Graph
/// and IMAP expose neither, so Outlook's and iCloud's providers don't conform: their signatures live on the device
/// alone, and they send from the account's own address.
public protocol SendAsSyncing: MailProvider {
    func sendAs() async throws -> SendAs

    /// Makes `text`, plain text, the signature the service keeps; empty removes it.
    func setSignature(_ text: String) async throws
}

public struct SendAs: Equatable, Sendable {
    /// The plain-text signature the service adds to new mail from this account; empty when there is none.
    public var signature: String
    /// The account's other addresses it can send from, each under the name the service gives it, if any.
    public var aliases: [Contact]

    public init(signature: String, aliases: [Contact]) {
        self.signature = signature
        self.aliases = aliases
    }
}
