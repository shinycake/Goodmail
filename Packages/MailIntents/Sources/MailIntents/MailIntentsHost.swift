import AppIntents
public import Foundation
public import MailCore

/// What the intents need from the process they run in: its mail, the commands that change it, and its windows. The
/// app registers one at launch with `registerMailIntentsHost(_:)`; every intent and query reads it as a dependency.
public protocol MailIntentsHost: Sendable {
    func accounts() throws -> [Account]
    /// The account's standard mailboxes and visible labels, named as the mailbox list names them.
    func mailboxes(of account: AccountID) throws -> [NamedMailbox]
    /// The stored threads among `ids`.
    func threads(_ ids: [ThreadSummary.ID]) throws -> [ThreadSummary]
    /// The newest `limit` threads in `mailbox`.
    func threads(in mailbox: Mailbox, limit: Int) throws -> [ThreadSummary]
    /// The newest `limit` threads search finds for `text` on the device.
    func threads(matching text: String, limit: Int) throws -> [ThreadSummary]
    /// The stored threads among `ids`, newest first, as filters see them.
    func threadFacts(_ ids: [ThreadSummary.ID]) throws -> [MailFacts]
    /// The cached messages of the threads, newest first, as filters see them.
    func messageFacts(inThreads ids: [ThreadSummary.ID]) throws -> [MailFacts]
    /// The cached messages that meet `condition`, newest first, as many as the store reads for a filter.
    func messageFacts(matching condition: MailCondition, in context: MailCondition.Context) throws -> [MailFacts]
    /// The stored threads that meet `condition`, newest first, each as its list row shows it.
    func threadFacts(matching condition: MailCondition, in context: MailCondition.Context) throws -> [MailFacts]
    /// Changes the threads through `MailCommands`, the only way intents change mail (ADR-011). Returns what undoes it.
    @discardableResult
    func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) async throws -> MailCommands.Undo
    /// Pins or unpins the threads through `MailCommands`. Returns what undoes it.
    @discardableResult
    func pin(_ threads: [ThreadSummary.ID], _ pinned: Bool) async throws -> MailCommands.Undo
    /// Snoozes the threads until `date`, or with `nil` wakes them now, through `MailCommands`. Returns what undoes it.
    @discardableResult
    func snooze(_ threads: [ThreadSummary.ID], until date: Date?) async throws -> MailCommands.Undo
    /// Leaves a mailing list for `account`'s reader (`ListUnsubscriber`).
    func unsubscribe(_ unsubscribe: Unsubscribe, account: AccountID) async throws -> ListUnsubscriber.Outcome
    /// Fetches new mail for every account.
    func refresh() async throws
    /// Takes back what `perform` or `pin` did, through `MailCommands`, when the system asks an intent to undo.
    func undo(_ undo: MailCommands.Undo) async throws
    /// Shows `route` in the frontmost window (ADR-011).
    @MainActor func open(_ route: Route)
}

/// A mailbox with the name the mailbox list gives it.
public struct NamedMailbox: Equatable, Sendable {
    public var mailbox: Mailbox
    public var name: String

    public init(mailbox: Mailbox, name: String) {
        self.mailbox = mailbox
        self.name = name
    }
}

extension MailIntentsHost {
    /// Makes this the host every intent uses. Call once, before the first intent can run.
    public func register() {
        let host: any MailIntentsHost = self
        registerMailIntentsHost { host }
    }
}

/// Makes the host `host` gives the one every intent uses, for a process whose host isn't ready at launch, as while
/// the app's database opens. Each intent waits for it, and fails with its error. Call once, before the first intent
/// can run.
public func registerMailIntentsHost(_ host: @escaping @Sendable () async throws -> any MailIntentsHost) {
    // Unsafe because App Intents declares `shared` nonisolated(unsafe). Safe: the manager is App Intents' own
    // registry for exactly this call, and this runs once at launch, before any intent can read it.
    unsafe AppDependencyManager.shared.add(dependency: host)
}
