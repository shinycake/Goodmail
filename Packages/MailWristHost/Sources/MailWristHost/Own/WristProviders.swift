import GmailProvider
public import MailCore
public import MailWrist
import OutlookProvider

#if canImport(FoundationNetworking)
    public import FoundationNetworking  // URLSession on Linux
#else
    public import Foundation
#endif

/// Builds the watch's own Gmail and Outlook clients from the sign-ins it holds (ADR-023). iCloud and other IMAP
/// accounts never get one: a watch app can't open the sockets IMAP needs (TN3135), so the iPhone serves them.
public struct WristProviders: Sendable {
    private let signIns: WristSignIns
    private let index: any MessageIndexStore
    private let http: any HTTPClient

    /// `index` is the watch's database, which Outlook uses to name the conversation of a deleted message.
    public init(signIns: WristSignIns, index: any MessageIndexStore, http: any HTTPClient = URLSession.shared) {
        self.signIns = signIns
        self.index = index
        self.http = http
    }

    /// A client for `account`, or `nil` when its service isn't reachable from the watch or its sign-in isn't here.
    public func provider(for account: WristAccount) throws -> (any MailProvider)? {
        guard let session = try session(for: account) else { return nil }
        return switch account.service {
        case .gmail: GmailClient(session: session, http: http)
        case .outlook: OutlookClient(session: session, index: index, http: http)
        case .icloud, .imap, nil: nil
        }
    }

    /// The account's OAuth session over the watch's sign-ins, when it holds one.
    func session(for account: WristAccount) throws -> OAuthSession? {
        guard let client = WristSignIns.client(for: account),
            try signIns.secrets.data(for: client.refreshTokenKey(account.id)) != nil
        else { return nil }
        return OAuthSession(accountID: account.id, client: client, http: http, keychain: signIns.secrets)
    }
}
