import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A byte stream to an IMAP or SMTP server that can turn on TLS in place, as STARTTLS asks. Production uses
/// `StreamTransport`; tests replay a transcript.
protocol MailTransport: Sendable {
    func send(_ data: Data) async throws
    /// The next bytes from the server, empty once it has closed the connection.
    func receive() async throws -> Data
    /// Starts TLS on the open connection, checking the server's certificate against its host name.
    func startTLS() async throws
    /// Closes the connection. Closing it again does nothing.
    func close() async
}

#if canImport(Network)
    /// A connection over a URLSession stream task, which can start TLS before the first byte, for
    /// `MailServer.Security.tls`, or in the middle of the connection, for STARTTLS. The Network framework's
    /// connections can't do the second, so one transport serves both.
    struct StreamTransport: MailTransport {
        private let task: URLSessionStreamTask

        /// Opens a connection to `server`. With `.tls`, TLS starts before the first byte; with `.startTLS`, the
        /// protocol starts it once the server agrees.
        init(to server: MailServer) {
            task = URLSession.shared.streamTask(withHostName: server.host, port: Int(server.port))
            task.resume()
            if server.security == .tls { task.startSecureConnection() }
        }

        func send(_ data: Data) async throws {
            try await task.write(data, timeout: 60)
        }

        func receive() async throws -> Data {
            try await task.readData(ofMinLength: 1, maxLength: 64 * 1024, timeout: 60).0 ?? Data()
        }

        func startTLS() async throws {
            task.startSecureConnection()
        }

        /// A stream task stays open, socket and all, until it is closed: dropping the transport doesn't close it.
        func close() async {
            task.closeWrite()
            task.closeRead()
            task.cancel()
        }
    }
#endif
