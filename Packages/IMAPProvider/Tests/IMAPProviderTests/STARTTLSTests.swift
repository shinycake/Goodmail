import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// Servers on IMAP's port 143 and SMTP's 587 talk in the clear until STARTTLS; those on 993 and 465 use TLS from the
/// start. Either way nothing secret goes out before TLS.
struct STARTTLSTests {
    @Test func imapTurnsOnTLSBeforeLoggingInAndForgetsWhatCameBefore() async throws {
        let transport = ScriptedTransport(
            transcript: """
                S: * OK [CAPABILITY IMAP4rev1 STARTTLS LOGINDISABLED] Dovecot ready.
                C: A1 STARTTLS
                S: A1 OK Begin TLS negotiation now.
                C: <TLS>
                C: A2 LOGIN "dana@example.com" "secret"
                S: A2 OK Logged in
                """)
        let connection = try await IMAPConnection(transport: transport, security: .startTLS)
        #expect(await connection.capabilities == nil, "what the server said in the clear can't be trusted")
        try await connection.login(user: "dana@example.com", password: "secret")
        #expect(await connection.state == .authenticated)
    }

    @Test func imapAsksForCapabilitiesWhenTheGreetingDoesntSay() async throws {
        let transport = ScriptedTransport(
            transcript: """
                S: * OK ready
                C: A1 CAPABILITY
                S: * CAPABILITY IMAP4rev1 STARTTLS
                S: A1 OK
                C: A2 STARTTLS
                S: A2 OK
                C: <TLS>
                """)
        _ = try await IMAPConnection(transport: transport, security: .startTLS)
        #expect(await transport.sent.last == "<TLS>\r\n")
    }

    @Test(arguments: [
        "S: * OK [CAPABILITY IMAP4rev1 AUTH=PLAIN] ready",
        "S: * PREAUTH [CAPABILITY IMAP4rev1 STARTTLS] logged in already",
    ])
    func imapGivesUpAConnectionThatStaysPlain(greeting: String) async throws {
        let transport = ScriptedTransport(transcript: greeting)
        await #expect(throws: IMAPError.insecure) {
            try await IMAPConnection(transport: transport, security: .startTLS)
        }
        #expect(await transport.sent.isEmpty)
    }

    @Test func smtpOverTLSSkipsSTARTTLS() async throws {
        let envelope = try #require(SMTPEnvelope(Data(SMTPTests.message.utf8)))
        let transport = ScriptedTransport(
            transcript: """
                S: 220 smtp.example.com ESMTP
                C: EHLO goodmail.app
                S: 250-smtp.example.com
                S: 250 AUTH PLAIN LOGIN
                C: AUTH PLAIN AGRhbmFAaWNsb3VkLmNvbQBhYmNkLWVmZ2gtaWprbC1tbm9w
                S: 235 OK
                C: MAIL FROM:<dana@icloud.com>
                S: 250 OK
                C: RCPT TO:<noa@example.com>
                S: 250 OK
                C: RCPT TO:<avi@example.com>
                S: 250 OK
                C: RCPT TO:<boss@example.com>
                S: 250 OK
                C: RCPT TO:<secret@example.com>
                S: 250 OK
                C: DATA
                S: 354 Go ahead
                C: From: Dana <dana@icloud.com>\\r\\nTo: noa@example.com, "Levi, Avi" <avi@example.com>\\r\\nSubject: Hi\\r\\nMessage-ID: <m1@icloud.com>\\r\\n\\r\\n..hidden line\\r\\nbye\\r\\n.
                S: 250 Queued
                C: QUIT
                S: 221 Bye
                """)
        try await SMTPClient(credentials: IMAPClientTests.credentials, security: .tls) { transport }.send(envelope)
    }
}
