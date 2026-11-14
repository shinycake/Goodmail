/// A provider whose service keeps the account's signature, so the signature is read from the service on each sync
/// and an edit is written back to it. Gmail keeps one on each send-as address. Graph and IMAP expose none, so
/// Outlook's and iCloud's providers don't conform and their signatures live on the device alone.
public protocol SignatureSyncing: MailProvider {
    /// The plain-text signature the service adds to new mail from this account; empty when there is none.
    func signature() async throws -> String

    /// Makes `text`, plain text, the signature the service keeps; empty removes it.
    func setSignature(_ text: String) async throws
}
