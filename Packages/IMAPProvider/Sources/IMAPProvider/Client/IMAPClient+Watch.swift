public import MailCore

extension IMAPClient: ChangeWatching {
    /// Keeps the Inbox in IDLE on a second connection, beside the one sync uses, since a connection in IDLE can do
    /// nothing else.
    public func watchChanges(_ changed: @escaping @Sendable () async -> Void) async throws {
        try await IMAPWatcher(connector: session.connector).watch(changed)
    }
}
