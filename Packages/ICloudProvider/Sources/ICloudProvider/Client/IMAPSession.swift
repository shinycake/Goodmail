import Foundation

/// The account's IMAP connection: opened and logged in on first use, opened again when the server has hung up, and
/// lent to one operation at a time, since an operation selects a folder and then reads it.
actor IMAPSession {
    struct Credentials: Sendable {
        var user: String
        var password: String
    }

    private enum State {
        case disconnected
        case connected(IMAPConnection)
    }

    private var state = State.disconnected
    private let credentials: Credentials
    private let connect: @Sendable () async throws -> any IMAPTransport
    /// The operation running now; the next one waits for it.
    private var tail: Task<Void, Never>?

    init(credentials: Credentials, connect: @escaping @Sendable () async throws -> any IMAPTransport) {
        self.credentials = credentials
        self.connect = connect
    }

    /// Runs `operation` after every operation started before it. Servers drop idle connections, so when the
    /// connection turns out to be closed, `operation` runs once more on a new one; operations only read, or make
    /// changes that are the same when made twice.
    func run<T: Sendable>(_ operation: @escaping @Sendable (IMAPConnection) async throws -> T) async throws -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            do {
                return try await operation(try await self.connection())
            } catch IMAPError.closed {
                self.state = .disconnected
                return try await operation(try await self.connection())
            }
        }
        tail = Task { _ = await task.result }
        return try await task.value
    }

    private func connection() async throws -> IMAPConnection {
        if case .connected(let connection) = state, await connection.state != .closed { return connection }
        state = .disconnected
        let connection = try await IMAPConnection(transport: try await connect())
        if await connection.state == .notAuthenticated {
            try await connection.login(user: credentials.user, password: credentials.password)
        }
        if await connection.capabilities.isEmpty { try await connection.refreshCapabilities() }
        // QRESYNC names the messages expunged since a cursor (RFC 7162 §3.2.6).
        if await connection.capabilities.contains("QRESYNC") { try await connection.enable("QRESYNC") }
        state = .connected(connection)
        return connection
    }
}
