import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A byte stream to an SMTP server that can turn on TLS in place, as STARTTLS asks (RFC 3207).
protocol SMTPTransport: Sendable {
    func send(_ data: Data) async throws
    /// The next bytes from the server, empty once it has closed the connection.
    func receive() async throws -> Data
    func startTLS() async throws
}

#if canImport(Network)
    /// iCloud takes mail on port 587, plain until STARTTLS. A URLSession stream task can switch to TLS in the middle
    /// of a connection, which the Network framework's connections can't.
    struct StreamTransport: SMTPTransport {
        private let task: URLSessionStreamTask

        init(host: String, port: Int) {
            task = URLSession.shared.streamTask(withHostName: host, port: port)
            task.resume()
        }

        func send(_ data: Data) async throws {
            try await task.write(data, timeout: 60)
        }

        func receive() async throws -> Data {
            try await task.readData(ofMinLength: 1, maxLength: 64 * 1024, timeout: 60).0 ?? Data()
        }

        /// Checks the server's certificate against the host name the task was made with.
        func startTLS() async throws {
            task.startSecureConnection()
        }
    }
#endif
