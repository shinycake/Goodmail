public import MailCore

/// Who reads and changes one account's mail for the watch (ADR-023). Only `WristAccountSources.resolve` decides it.
public enum WristAccountSource: Codable, Equatable, Sendable {
    /// The watch does, at the account's service.
    case direct
    /// The iPhone does, as ADR-022 describes.
    case relayed(Reason)

    /// Why the iPhone serves an account.
    public enum Reason: Codable, Equatable, Sendable {
        /// iCloud or another IMAP account: watchOS doesn't allow its connection. Also an account from an iPhone too
        /// old to say its service.
        case service
        /// The owner turned "Mail Without iPhone" off.
        case switchedOff
        /// Its sign-in hasn't reached this watch's Keychain.
        case noSignIn
        /// The service turned the sign-in down. Signing in again on the iPhone fixes it.
        case signInRejected
        /// The watch is still fetching its first copy of the Inbox.
        case filling
    }
}

/// Decides each account's source from what the watch knows about it.
public enum WristAccountSources {
    /// The source of each of `accounts`. `signIns` are the accounts whose sign-in is in the watch's Keychain;
    /// `health` and `syncStates` are the watch's own syncs of them.
    public static func resolve(
        accounts: [WristAccount], signIns: Set<AccountID>, health: [AccountID: AccountHealth],
        syncStates: [AccountID: SyncState], independence: WristIndependence
    ) -> [AccountID: WristAccountSource] {
        // A snapshot that lists an account twice keeps its first entry rather than trapping.
        Dictionary(
            accounts.map { account in
                (
                    account.id,
                    source(
                        of: account, signedIn: signIns.contains(account.id), health: health[account.id] ?? .healthy,
                        sync: syncStates[account.id], independence: independence)
                )
            },
            uniquingKeysWith: { first, _ in first })
    }

    /// The first reason the watch can't read the account itself, in order from the most lasting; direct when there is
    /// none.
    private static func source(
        of account: WristAccount, signedIn: Bool, health: AccountHealth, sync: SyncState?,
        independence: WristIndependence
    ) -> WristAccountSource {
        guard let service = account.service, service.isReachableFromWatch else { return .relayed(.service) }
        guard independence == .on else { return .relayed(.switchedOff) }
        guard signedIn else { return .relayed(.noSignIn) }
        if health == .needsSignIn { return .relayed(.signInRejected) }
        guard case .current = sync else { return .relayed(.filling) }
        return .direct
    }
}

extension MailService {
    /// Whether the watch can talk to the service itself: over HTTPS, which watchOS allows. IMAP and SMTP need a raw
    /// TLS socket, which it doesn't (TN3135).
    var isReachableFromWatch: Bool {
        switch self {
        case .gmail, .outlook: true
        case .icloud, .imap: false
        }
    }
}
