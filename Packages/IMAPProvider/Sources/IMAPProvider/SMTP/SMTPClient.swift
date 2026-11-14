import Foundation

/// Submits messages over SMTP (RFC 5321) with AUTH PLAIN, over TLS or after STARTTLS, one connection per message:
/// mail is sent one message at a time, seconds or hours apart, so there's no session worth keeping open.
struct SMTPClient: Sendable {
    let credentials: IMAPCredentials
    let security: MailServer.Security
    let connect: @Sendable () async throws -> any MailTransport

    /// Sends `envelope` on a connection of its own, which is closed however the send ends.
    func send(_ envelope: SMTPEnvelope) async throws {
        let transport = try await connect()
        do {
            try await send(envelope, over: transport)
        } catch {
            await transport.close()
            throw error
        }
        await transport.close()
    }

    private func send(_ envelope: SMTPEnvelope, over transport: any MailTransport) async throws {
        var conversation = SMTPConversation(transport: transport)
        try await conversation.expect(220)
        let features = try await conversation.command("EHLO goodmail.app", expect: 250).lines.map { $0.uppercased() }
        if security == .startTLS {
            guard features.contains(where: { $0.hasPrefix("STARTTLS") }) else { throw SMTPError.insecure }
            try await conversation.command("STARTTLS", expect: 220)
            try await conversation.startTLS()
            // The server forgets everything from before TLS, EHLO included (RFC 3207 §4.2).
            try await conversation.command("EHLO goodmail.app", expect: 250)
        }
        let login = Data("\0\(credentials.user)\0\(credentials.password)".utf8).base64EncodedString()
        do {
            try await conversation.command("AUTH PLAIN \(login)", expect: 235)
        } catch SMTPError.refused(let reply) where reply.code == 535 {
            throw SMTPError.authenticationFailed
        }
        try await conversation.command("MAIL FROM:<\(envelope.from)>", expect: 250)
        for recipient in envelope.recipients {
            try await conversation.command("RCPT TO:<\(recipient)>", expect: 250, 251)
        }
        try await conversation.command("DATA", expect: 354)
        try await conversation.send(SMTPEnvelope.dotStuffed(envelope.message) + Data(".\r\n".utf8), expect: 250)
        // The message is sent; a QUIT that fails changes nothing.
        try? await conversation.command("QUIT", expect: 221)
    }
}

/// One exchange of commands and replies.
private struct SMTPConversation {
    let transport: any MailTransport
    private var reader = SMTPReader()

    init(transport: any MailTransport) {
        self.transport = transport
    }

    @discardableResult
    mutating func command(_ line: String, expect codes: Int...) async throws -> SMTPReply {
        try await send(Data((line + "\r\n").utf8), expect: codes)
    }

    @discardableResult
    mutating func send(_ data: Data, expect codes: Int...) async throws -> SMTPReply {
        try await send(data, expect: codes)
    }

    private mutating func send(_ data: Data, expect codes: [Int]) async throws -> SMTPReply {
        try await transport.send(data)
        return try await expect(codes)
    }

    @discardableResult
    mutating func expect(_ codes: Int...) async throws -> SMTPReply {
        try await expect(codes)
    }

    private mutating func expect(_ codes: [Int]) async throws -> SMTPReply {
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
