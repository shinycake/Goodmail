import Foundation
import MailCore

/// Opens the account's IMAP connections, logged in and ready: the session's, and the one that waits in IDLE.
struct IMAPConnector: Sendable {
    let credentials: IMAPCredentials
    let security: MailServer.Security
    let connect: @Sendable () async throws -> any MailTransport

    /// A new connection, logged in, with its capabilities read and QRESYNC on where the server has it. A connection
    /// that fails on the way is closed.
    func open() async throws -> IMAPConnection {
        let connection = try await IMAPConnection(transport: try await connect(), security: security)
        do {
            if await connection.state == .notAuthenticated {
                try await connection.login(user: credentials.user, password: credentials.password)
            }
            // QRESYNC names the messages expunged since a cursor (RFC 7162 §3.2.6).
            if try await connection.supports("QRESYNC") { try await connection.enable("QRESYNC") }
        } catch {
            await connection.close()
            throw error
        }
        return connection
    }
}
