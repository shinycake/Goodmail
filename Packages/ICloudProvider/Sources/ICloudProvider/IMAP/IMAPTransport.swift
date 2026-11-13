import Foundation
import Network

/// A byte stream to an IMAP server. Production uses TLS; tests replay a transcript.
protocol IMAPTransport: Sendable {
    func send(_ data: Data) async throws
    /// The next bytes from the server, empty once it has closed the connection.
    func receive() async throws -> Data
}

/// Implicit TLS, as iCloud serves IMAP on port 993.
struct TLSTransport: IMAPTransport {
    private let connection: NetworkConnection<TLS>

    init(host: String, port: UInt16) {
        connection = NetworkConnection(to: .hostPort(host: .init(host), port: .init(integerLiteral: port))) { TLS() }
    }

    func send(_ data: Data) async throws {
        try await connection.send(data)
    }

    func receive() async throws -> Data {
        let message = try await connection.receive(atLeast: 1, atMost: 64 * 1024)
        return message.content
    }
}
