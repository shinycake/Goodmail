import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// A stream task stays open until it's closed, so every way a connection ends closes it.
struct ClosingTests {
    @Test func aConnectionThatStaysPlainIsClosed() async throws {
        let transport = ScriptedTransport(transcript: "S: * OK [CAPABILITY IMAP4rev1] ready")
        await #expect(throws: IMAPError.insecure) {
            try await IMAPConnection(transport: transport, security: .startTLS)
        }
        #expect(await transport.isClosed)
    }

    @Test func loggingOutClosesTheConnection() async throws {
        let transport = ScriptedTransport(transcript: "S: * PREAUTH ready\nC: A1 LOGOUT\nS: * BYE\nS: A1 OK")
        let connection = try await IMAPConnection(transport: transport, security: .tls)
        #expect(await !transport.isClosed)
        try await connection.logout()
        #expect(await transport.isClosed)
    }

    @Test func aServerThatHangsUpIsClosed() async throws {
        let transport = ScriptedTransport(transcript: "S: * PREAUTH ready\nC: A1 LIST \"\" \"*\"")
        let connection = try await IMAPConnection(transport: transport, security: .tls)
        await #expect(throws: IMAPError.closed) { try await connection.mailboxes() }
        #expect(await transport.isClosed)
    }

    @Test func aRefusedLoginInTheSessionClosesItsConnection() async throws {
        let transport = ScriptedTransport(
            transcript:
                "S: * OK ready\nC: A1 LOGIN \"dana@icloud.com\" \"abcd-efgh-ijkl-mnop\"\nS: A1 NO [AUTHENTICATIONFAILED] no"
        )
        let session = IMAPSession(credentials: IMAPClientTests.credentials, security: .tls) { transport }
        await #expect(throws: IMAPError.authenticationFailed) { try await session.run { _ in } }
        #expect(await transport.isClosed)
    }

    @Test(arguments: [true, false])
    func anSMTPSendClosesItsConnectionHoweverItEnds(succeeds: Bool) async throws {
        let envelope = try #require(SMTPEnvelope(Data(SMTPTests.message.utf8)))
        let transcript =
            succeeds
            ? SMTPTests.submission
            : SMTPTests.submission.split(separator: "\n").prefix(12).joined(separator: "\n") + "\nS: 535 no"
        let transport = ScriptedTransport(transcript: transcript)
        let client = SMTPClient(credentials: IMAPClientTests.credentials, security: .startTLS) { transport }
        if succeeds {
            try await client.send(envelope)
        } else {
            await #expect(throws: SMTPError.authenticationFailed) { try await client.send(envelope) }
        }
        #expect(await transport.isClosed)
    }
}
