import Foundation

/// One exchange of commands and replies with an SMTP server.
struct SMTPConversation {
    let transport: any MailTransport
    /// The extensions the server's last EHLO listed, upper-cased.
    var features: [String] = []
    private var reader = SMTPReader()

    init(transport: any MailTransport) {
        self.transport = transport
    }

    /// Whether the server takes several commands before it answers them (RFC 2920).
    var pipelines: Bool { features.contains("PIPELINING") }

    @discardableResult
    mutating func command(_ line: String, expect codes: Int...) async throws -> SMTPReply {
        try await send(Data((line + "\r\n").utf8), expect: codes)
    }

    @discardableResult
    mutating func send(_ data: Data, expect codes: Int...) async throws -> SMTPReply {
        try await send(data, expect: codes)
    }

    @discardableResult
    mutating func send(_ data: Data, expect codes: [Int]) async throws -> SMTPReply {
        try await transport.send(data)
        return try await expect(codes)
    }

    @discardableResult
    mutating func expect(_ codes: Int...) async throws -> SMTPReply {
        try await expect(codes)
    }

    @discardableResult
    mutating func expect(_ codes: [Int]) async throws -> SMTPReply {
        let reply = try await nextReply()
        guard codes.contains(reply.code) else { throw SMTPError.refused(reply) }
        return reply
    }

    /// Bytes that came before TLS can't be trusted (RFC 3207 §6), so they are dropped.
    mutating func startTLS() async throws {
        try await transport.startTLS()
        reader = SMTPReader()
    }

    private mutating func nextReply() async throws -> SMTPReply {
        while true {
            if let reply = try reader.next() { return reply }
            let bytes = try await transport.receive()
            guard !bytes.isEmpty else { throw SMTPError.closed }
            reader.append(bytes)
        }
    }
}
