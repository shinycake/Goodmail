import Foundation

/// Submits messages over SMTP (RFC 5321), over TLS or after STARTTLS, one connection per message: mail is sent one
/// message at a time, seconds or hours apart, so there's no session worth keeping open.
struct SMTPClient: Sendable {
    let credentials: IMAPCredentials
    let security: MailServer.Security
    let connect: @Sendable () async throws -> any MailTransport

    /// Sends `envelope` on a connection of its own, which is closed however the send ends.
    func send(_ envelope: SMTPEnvelope) async throws {
        try await withLoggedInConversation { conversation in
            try await conversation.command("MAIL FROM:<\(envelope.from)>", expect: 250)
            for recipient in envelope.recipients {
                try await conversation.command("RCPT TO:<\(recipient)>", expect: 250, 251)
            }
            try await conversation.command("DATA", expect: 354)
            try await conversation.send(
                SMTPEnvelope.dotStuffed(envelope.message) + Data(".\r\n".utf8), expect: 250)
            // The message is sent; a QUIT that fails changes nothing.
            try? await conversation.command("QUIT", expect: 221)
        }
    }

    /// Opens a connection, logs in and runs `body` on the conversation, then closes the connection however it
    /// ended.
    private func withLoggedInConversation(_ body: (inout SMTPConversation) async throws -> Void) async throws {
        let transport = try await connect()
        do {
            var conversation = try await loggedIn(over: transport)
            try await body(&conversation)
        } catch {
            await transport.close()
            throw error
        }
        await transport.close()
    }

    /// A conversation over `transport` that is encrypted and logged in, ready for a message.
    private func loggedIn(over transport: any MailTransport) async throws -> SMTPConversation {
        var conversation = SMTPConversation(transport: transport)
        try await conversation.expect(220)
        var features = try await conversation.command("EHLO goodmail.app", expect: 250).features
        if security == .startTLS {
            guard features.contains(where: { $0.hasPrefix("STARTTLS") }) else { throw SMTPError.insecure }
            try await conversation.command("STARTTLS", expect: 220)
            try await conversation.startTLS()
            // The server forgets everything from before TLS, EHLO included (RFC 3207 §4.2).
            features = try await conversation.command("EHLO goodmail.app", expect: 250).features
        }
        do {
            try await logIn(on: &conversation, with: SMTPAuthentication(features: features))
        } catch SMTPError.refused(let reply) where reply.code == 535 {
            throw SMTPError.authenticationFailed
        }
        return conversation
    }

    private func logIn(on conversation: inout SMTPConversation, with mechanism: SMTPAuthentication) async throws {
        func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }
        switch mechanism {
        case .plain:
            try await conversation.command(
                "AUTH PLAIN \(base64("\0\(credentials.user)\0\(credentials.password)"))", expect: 235)
        case .login:
            try await conversation.command("AUTH LOGIN", expect: 334)
            try await conversation.command(base64(credentials.user), expect: 334)
            try await conversation.command(base64(credentials.password), expect: 235)
        }
    }
}

/// How the client logs in: PLAIN (RFC 4616) where the server offers it, else LOGIN, which Exchange offers alone.
enum SMTPAuthentication: Equatable {
    case plain
    case login

    /// From EHLO's `AUTH PLAIN LOGIN` line, or the older `AUTH=LOGIN`. A server that lists neither gets PLAIN.
    init(features: [String]) {
        let mechanisms = Set(
            features.filter { $0.hasPrefix("AUTH ") || $0.hasPrefix("AUTH=") }
                .flatMap { $0.dropFirst(5).split(separator: " ").map(String.init) })
        self = !mechanisms.contains("PLAIN") && mechanisms.contains("LOGIN") ? .login : .plain
    }
}

extension SMTPReply {
    /// The extensions an EHLO reply lists, upper-cased, after the line that names the server.
    fileprivate var features: [String] { lines.dropFirst().map { $0.uppercased() } }
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
