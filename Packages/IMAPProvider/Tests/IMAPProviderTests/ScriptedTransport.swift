import Foundation

@testable import IMAPProvider

/// Replays an IMAP conversation: each command sent must be the next `C:` line, and each receive returns the server
/// lines up to the next command, in chunks of `chunkSize` bytes to exercise framing. A `-- dropped` line fails the
/// socket from there on. A `-- silent` line is a server with nothing to say: a read waits until the client sends
/// something or closes the connection, as a server in IDLE does.
actor ScriptedTransport: MailTransport {
    enum Step {
        case client(String)
        case server(String)
        /// The socket fails, as one the server dropped while it was idle does: sending or reading throws.
        case dropped
        /// The server says nothing until the client does.
        case silent
    }

    /// What a socket the server dropped throws: `Network.NWError` 57, socket is not connected.
    static let notConnected = NSError(domain: "Network.NWError", code: 57)

    struct Unexpected: Error, CustomStringConvertible {
        let description: String
    }

    private var steps: [Step]
    private var pending = Data()
    private let chunkSize: Int
    private(set) var sent: [String] = []
    /// Whether the client closed the connection.
    private(set) var isClosed = false
    /// A read waiting out a `-- silent` step.
    private var silence: CheckedContinuation<Void, Never>?

    init(_ steps: [Step], chunkSize: Int = .max) {
        self.steps = steps
        self.chunkSize = chunkSize
    }

    /// `C: ` and `S: ` lines, each sent or answered with CRLF. A line may hold more CRLFs, written `\r\n`.
    init(transcript: String, chunkSize: Int = .max) {
        let steps = transcript.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> Step? in
            if line.hasPrefix("C: ") { return .client(String(line.dropFirst(3)).replacing("\\r\\n", with: "\r\n")) }
            if line.hasPrefix("S: ") { return .server(String(line.dropFirst(3)).replacing("\\r\\n", with: "\r\n")) }
            if line == "-- dropped" { return .dropped }
            if line == "-- silent" { return .silent }
            return nil
        }
        self.init(steps, chunkSize: chunkSize)
    }

    func send(_ data: Data) async throws {
        if case .dropped = steps.first { throw Self.notConnected }
        let line = String(decoding: data, as: UTF8.self)
        sent.append(line)
        guard case .client(let expected) = steps.first, line == expected + "\r\n" else {
            throw Unexpected(description: "sent \(line.debugDescription), expected \(String(describing: steps.first))")
        }
        steps.removeFirst()
        endSilence()
    }

    /// Expects a `C: <TLS>` step.
    func startTLS() async throws {
        try await send(Data("<TLS>\r\n".utf8))
    }

    func close() async {
        isClosed = true
        endSilence()
    }

    func receive(timeout: Duration) async throws -> Data {
        if pending.isEmpty, case .silent = steps.first {
            steps.removeFirst()
            await withCheckedContinuation { silence = $0 }
        }
        if isClosed { throw Self.notConnected }
        if pending.isEmpty, case .dropped = steps.first { throw Self.notConnected }
        while pending.isEmpty, case .server(let line) = steps.first {
            pending.append(Data((line + "\r\n").utf8))
            steps.removeFirst()
        }
        let chunk = pending.prefix(chunkSize)
        pending.removeFirst(chunk.count)
        return Data(chunk)
    }

    private func endSilence() {
        silence?.resume()
        silence = nil
    }
}
