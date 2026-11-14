import Foundation
import MailCore

/// The account's IMAP connection: opened and logged in on first use, opened again when the server has hung up, and
/// lent to one operation at a time, since an operation selects a folder and then reads it.
actor IMAPSession {
    private enum State {
        case disconnected
        case connected(IMAPConnection)
    }

    private var state = State.disconnected
    private let credentials: IMAPCredentials
    private let security: MailServer.Security
    private let connect: @Sendable () async throws -> any MailTransport
    private var queue = SerialQueue()

    init(
        credentials: IMAPCredentials, security: MailServer.Security,
        connect: @escaping @Sendable () async throws -> any MailTransport
    ) {
        self.credentials = credentials
        self.security = security
        self.connect = connect
    }

    /// Runs `operation` after every operation started before it. Servers drop idle connections, saying BYE, ending
    /// the stream or leaving a socket that fails on the next write; whichever way, the connection closes, and
    /// `operation` runs once more on a new one. Operations read, or make changes that are the same when made twice,
    /// except COPY: a connection lost between the server's copy and its reply files a second copy, which shows as one
    /// message, since threads count copies once.
    func run<T: Sendable>(_ operation: @escaping @Sendable (IMAPConnection) async throws -> T) async throws -> T {
        try await queue.run {
            let connection = try await self.connection()
            do {
                return try await operation(connection)
            } catch {
                guard await connection.state == .closed, !Task.isCancelled else { throw error }
                await self.disconnect()
                return try await operation(try await self.connection())
            }
        }.value
    }

    private func disconnect() async {
        if case .connected(let connection) = state { await connection.close() }
        state = .disconnected
    }

    private func connection() async throws -> IMAPConnection {
        if case .connected(let connection) = state, await connection.state != .closed { return connection }
        await disconnect()
        let connection = try await IMAPConnection(transport: try await connect(), security: security)
        do {
            if await connection.state == .notAuthenticated {
                try await connection.login(user: credentials.user, password: credentials.password)
            }
            if await connection.capabilities == nil { try await connection.refreshCapabilities() }
            // QRESYNC names the messages expunged since a cursor (RFC 7162 §3.2.6).
            if await connection.capabilities?.contains("QRESYNC") == true {
                try await connection.enable("QRESYNC")
            }
        } catch {
            await connection.close()
            throw error
        }
        state = .connected(connection)
        return connection
    }
}
