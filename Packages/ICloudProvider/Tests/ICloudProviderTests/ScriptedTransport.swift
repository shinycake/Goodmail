import Foundation

@testable import ICloudProvider

/// Replays an IMAP conversation: each command sent must be the next `C:` line, and each receive returns the server
/// lines up to the next command, in chunks of `chunkSize` bytes to exercise framing.
actor ScriptedTransport: IMAPTransport, SMTPTransport {
    enum Step {
        case client(String)
        case server(String)
    }

    struct Unexpected: Error, CustomStringConvertible {
        let description: String
    }

    private var steps: [Step]
    private var pending = Data()
    private let chunkSize: Int
    private(set) var sent: [String] = []

    init(_ steps: [Step], chunkSize: Int = .max) {
        self.steps = steps
        self.chunkSize = chunkSize
    }

    /// `C: ` and `S: ` lines, each sent or answered with CRLF. A line may hold more CRLFs, written `\r\n`.
    init(transcript: String, chunkSize: Int = .max) {
        let steps = transcript.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> Step? in
            if line.hasPrefix("C: ") { return .client(String(line.dropFirst(3)).replacing("\\r\\n", with: "\r\n")) }
            if line.hasPrefix("S: ") { return .server(String(line.dropFirst(3)).replacing("\\r\\n", with: "\r\n")) }
            return nil
        }
        self.init(steps, chunkSize: chunkSize)
    }

    func send(_ data: Data) async throws {
        let line = String(decoding: data, as: UTF8.self)
        sent.append(line)
        guard case .client(let expected) = steps.first, line == expected + "\r\n" else {
            throw Unexpected(description: "sent \(line.debugDescription), expected \(String(describing: steps.first))")
        }
        steps.removeFirst()
    }

    /// Expects a `C: <TLS>` step.
    func startTLS() async throws {
        try await send(Data("<TLS>\r\n".utf8))
    }

    func receive() async throws -> Data {
        while pending.isEmpty, case .server(let line) = steps.first {
            pending.append(Data((line + "\r\n").utf8))
            steps.removeFirst()
        }
        let chunk = pending.prefix(chunkSize)
        pending.removeFirst(chunk.count)
        return Data(chunk)
    }
}
