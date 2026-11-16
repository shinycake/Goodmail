public import Foundation
public import MailCore
public import MailStore
import OSLog

/// What the notification extension does with a new-mail push: catches the account up on what changed and picks
/// what alerts. The mail it fetches is stored, so the app shows it on open without fetching it again (ADR-002).
public struct NewMailFetch: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Mail to alert for, newest first.
        case alerts([NewMail], in: Account)
        /// Nothing in the push alerts: a read, an archive, mail already seen, or alerts turned off.
        case nothingNew
    }

    public enum Failure: Error, Equatable {
        /// The push names no account, so it isn't one of the relay's.
        case notANewMailPush
        /// No account on this device is the push's, as after removing it.
        case unknownAccount
    }

    private let database: MailDatabase
    private let provider: @Sendable (Account) throws -> any MailProvider
    private let notify: @Sendable ([RuleAlert], Account) async -> Void
    private let now: @Sendable () -> Date

    /// `provider` makes the provider for an account the push names; `notify` posts the notifications the reader's
    /// rules ask for.
    public init(
        database: MailDatabase,
        notify: @escaping @Sendable ([RuleAlert], Account) async -> Void = { _, _ in },
        provider: @escaping @Sendable (Account) throws -> any MailProvider,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.database = database
        self.provider = provider
        self.notify = notify
        self.now = now
    }

    /// How the relay's payload names the account (PushWorker/README.md).
    public enum Target: Equatable, Sendable {
        /// Gmail: by address, the only thing Gmail's notification says.
        case address(String)
        /// Outlook: by the app's own ID, which the device registered with its subscription.
        case account(AccountID)
    }

    public static func target(in userInfo: [AnyHashable: Any]) -> Target? {
        if let id = userInfo["accountID"] as? String { return .account(AccountID(rawValue: id)) }
        return (userInfo["account"] as? String).map(Target.address)
    }

    /// The app badge after the fetch, as `MailDatabase.badgeCount()` counts it.
    public func badgeCount() throws -> Int {
        try database.badgeCount()
    }

    public func run(_ target: Target) async throws -> Outcome {
        let accounts = try database.accounts()
        let match: Account? =
            switch target {
            case .address(let address):
                accounts.first { $0.email.caseInsensitiveCompare(address) == .orderedSame }
            case .account(let id): accounts.first { $0.id == id }
            }
        guard let account = match else { throw Failure.unknownAccount }
        let client = try provider(account)
        let caughtUp = try await SyncEngine(accountID: account.id, provider: client, store: database).catchUp()
        await runRules(in: account, provider: client)
        // As the rules left them: one they archived, read or moved no longer alerts.
        let arrived = try database.threads(caughtUp.map(\.id))
        let threads = try database.claimAlerts(among: arrived, in: account, now: now())
        guard !threads.isEmpty else { return .nothingNew }
        let codes = await withTaskGroup(of: (Int, OneTimeCode?).self) { group in
            for (index, thread) in threads.enumerated() {
                group.addTask { (index, await Self.unshownCode(in: thread, from: client)) }
            }
            return await group.reduce(into: [Int: OneTimeCode]()) { $0[$1.0] = $1.1 }
        }
        return .alerts(threads.enumerated().map { NewMail(thread: $1, code: codes[$0]) }, in: account)
    }

    /// Runs the reader's rules on the mail that just arrived, and sends what they changed to the provider before the
    /// extension ends. A failure leaves the mail as it came and the alerts as they would be.
    private func runRules(in account: Account, provider client: any MailProvider) async {
        let commands = MailCommands(store: database, replay: { _ in }, now: now)
        do {
            let run = try await RuleRunner(store: database, provider: client, commands: commands, now: now)
                .run(for: account.id)
            run.logFailures(after: "a push")
            // The alerts go out even when what the rules changed can't reach the provider yet: the change is kept
            // in the Outbox for the app to send.
            if !run.alerts.isEmpty { await notify(run.alerts, account) }
            try await Outbox(accountID: account.id, provider: client, store: database, now: now).flush()
        } catch {
            RuleRun.log.error("Rules after a push failed: \(error, privacy: .public)")
        }
    }

    /// The one-time code in a thread's latest message when its subject or snippet names one without giving it, as
    /// "Your sign-in code" over a snippet that ends before the code does. A body that can't be read costs only the
    /// code: the alert shows the snippet, as for any mail.
    private static func unshownCode(in thread: ThreadSummary, from provider: any MailProvider) async -> OneTimeCode? {
        let shown = "\(thread.subject)\n\(thread.snippet)"
        guard OneTimeCode.isNamed(in: shown), OneTimeCode(in: shown) == nil,
            let latest = try? await provider.messages(inThread: thread.id.threadID).last
        else { return nil }
        return OneTimeCode(in: latest.body.text)
    }
}
