import AppIntents
import MailCore

/// What the intents need from the process they run in: its mail, the commands that change it, and its windows. The
/// app registers one at launch with `register(_:)`; every intent and query reads it as a dependency.
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
    /// The thread's cached messages, oldest first; empty when none are.
    func cachedMessages(inThread id: ThreadSummary.ID) throws -> [Message]
    /// Changes the threads through `MailCommands`, the only way intents change mail (ADR-011). Returns what undoes it.
    @discardableResult
    func perform(_ action: ThreadAction, on threads: [ThreadSummary.ID]) async throws -> MailCommands.Undo
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
        AppDependencyManager.shared.add(dependency: host)
    }
}
