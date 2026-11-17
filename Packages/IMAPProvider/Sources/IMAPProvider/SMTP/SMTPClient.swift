import Foundation
import MailCore

/// Submits messages over SMTP (RFC 5321), over TLS or after STARTTLS, one connection per message: mail is sent one
/// message at a time, seconds or hours apart, so there's no session worth keeping open. A send that waits out an undo
/// window logs in during it (`prepare`), so only the message is left when it goes.
struct SMTPClient: Sendable {
    let credentials: IMAPCredentials
    let security: MailServer.Security
    let connect: @Sendable () async throws -> any MailTransport
    /// The connection `prepare` opened, until a send takes it.
    let waiting = SMTPWaitingConnection()

    init(
        credentials: IMAPCredentials, security: MailServer.Security,
        connect: @escaping @Sendable () async throws -> any MailTransport
    ) {
        self.credentials = credentials
        self.security = security
        self.connect = connect
    }

    /// Opens and logs in the connection the next `send` uses, without waiting for it.
    func prepare() async {
        await waiting.open { [self] in
            let transport = try await connect()
            do {
                return try await loggedIn(over: transport)
            } catch {
                await transport.close()
                throw error
            }
        }
    }

    /// Sends `envelope` on the connection `prepare` opened, or on one of its own, and closes it however the send
    /// ends. A prepared connection that fails before the message itself goes, as one the server dropped while it
    /// waited, is replaced by a new one: until then the server has nothing to deliver.
    func send(_ envelope: SMTPEnvelope) async throws {
        if var conversation = await waiting.take() {
            var messageWent = false
            do {
                try await submit(envelope, on: &conversation, messageWent: &messageWent)
                return await quit(conversation)
            } catch SMTPError.refused(let reply) where reply.isPermanentFailure {
                await conversation.transport.close()
                throw SMTPError.refused(reply)
            } catch {
                await conversation.transport.close()
                if messageWent { throw error }
            }
        }
        try await withLoggedInConversation { conversation in
            var messageWent = false
            try await submit(envelope, on: &conversation, messageWent: &messageWent)
            _ = try? await conversation.command("QUIT", expect: 221)
        }
    }

    /// The envelope, then the message. With PIPELINING, the envelope's commands go in one write and their replies
    /// are read after, saving a round trip each. `messageWent` turns true as the message itself starts out.
    private func submit(
        _ envelope: SMTPEnvelope, on conversation: inout SMTPConversation, messageWent: inout Bool
    ) async throws {
        let commands =
            ["MAIL FROM:<\(envelope.from)>"] + envelope.recipients.map { "RCPT TO:<\($0)>" } + ["DATA"]
        let replies = [[250]] + envelope.recipients.map { _ in [250, 251] } + [[354]]
        if conversation.pipelines {
            try await conversation.transport.send(Data(commands.map { $0 + "\r\n" }.joined().utf8))
            for codes in replies { try await conversation.expect(codes) }
        } else {
            for (command, codes) in zip(commands, replies) {
                try await conversation.send(Data((command + "\r\n").utf8), expect: codes)
            }
        }
        messageWent = true
        try await conversation.send(SMTPEnvelope.dotStuffed(envelope.message) + Data(".\r\n".utf8), expect: 250)
    }

    /// The message is sent; a QUIT that fails changes nothing.
    private func quit(_ conversation: SMTPConversation) async {
        var conversation = conversation
        _ = try? await conversation.command("QUIT", expect: 221)
        await conversation.transport.close()
    }

    /// Logs in and leaves, to check the user name and password before an account is added.
    func verify() async throws {
        try await withLoggedInConversation { conversation in
            _ = try? await conversation.command("QUIT", expect: 221)
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
        conversation.features = features
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
