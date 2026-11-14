import Foundation
import MailCore
import MailStore

/// What the notification extension does with a new-mail push: catches the account up on what changed and picks
/// what alerts. The mail it fetches is stored, so the app shows it on open without fetching it again (ADR-002).
public struct NewMailFetch: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Threads to alert for, newest first.
        case alerts([ThreadSummary], in: Account)
        /// Nothing in the push alerts: a read, an archive, mail already seen, or alerts turned off.
        case nothingNew
    }

    public enum Failure: Error, Equatable {
        /// The push names no address, so it isn't one of the relay's.
        case notANewMailPush
        /// No account on this device has the push's address, as after removing it.
        case unknownAccount
    }

    private let database: MailDatabase
    private let provider: @Sendable (Account) throws -> any MailProvider
    private let now: @Sendable () -> Date

    /// `provider` makes the provider for an account the push names.
    public init(
        database: MailDatabase, provider: @escaping @Sendable (Account) throws -> any MailProvider,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.database = database
        self.provider = provider
        self.now = now
    }

    /// The relay's payload names the account by address (PushWorker/README.md).
    public static func address(in userInfo: [AnyHashable: Any]) -> String? {
        userInfo["account"] as? String
    }

    /// The app badge after the fetch, as `MailDatabase.badgeCount()` counts it.
    public func badgeCount() throws -> Int {
        try database.badgeCount()
    }

    public func run(address: String) async throws -> Outcome {
        guard
            let account = try database.accounts().first(where: {
                $0.email.caseInsensitiveCompare(address) == .orderedSame
            })
        else { throw Failure.unknownAccount }
        let arrived = try await SyncEngine(accountID: account.id, provider: try provider(account), store: database)
            .catchUp()
        let threads = try database.claimAlerts(among: arrived, in: account, now: now())
        return threads.isEmpty ? .nothingNew : .alerts(threads, in: account)
    }
}
