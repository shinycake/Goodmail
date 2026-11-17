import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// A send whose undo window lets it log in first, and servers that take the envelope in one write.
struct SMTPPreparedTests {
    private let envelope = SMTPEnvelope(Data(SMTPTests.message.utf8))!
    private let lines = SMTPTests.submission.split(separator: "\n").map(String.init)
    /// Up to and including the server's 235 to AUTH.
    private var login: [String] { Array(lines.prefix(13)) }
    /// From MAIL FROM to the server's 221 to QUIT.
    private var message: [String] { Array(lines.dropFirst(13)) }

    private func client(_ transcripts: [String]) -> (SMTPClient, [ScriptedTransport]) {
        let scripted = transcripts.map { ScriptedTransport(transcript: $0) }
        let transports = Transports(scripted)
        let client = SMTPClient(credentials: IMAPClientTests.credentials, security: .startTLS) {
            try await transports.next()
        }
        return (client, scripted)
    }

    @Test func preparingLogsInWithoutSending() async throws {
        let (client, transports) = client([login.joined(separator: "\n")])
        await client.prepare()
        let conversation = try #require(await client.waiting.take())
        #expect(conversation.features.contains("AUTH PLAIN LOGIN"))
        #expect(await !transports[0].isClosed)
    }

    @Test func aPreparedSendUsesTheConnectionThatLoggedInAhead() async throws {
        let (client, transports) = client([(login + message).joined(separator: "\n")])
        await client.prepare()
        try await client.send(envelope)
        #expect(await transports[0].isClosed)
    }

    @Test func preparingTwiceOpensOneConnection() async throws {
        let (client, _) = client([(login + message).joined(separator: "\n")])
        await client.prepare()
        await client.prepare()
        try await client.send(envelope)
    }

    @Test func aPreparedConnectionTheServerDroppedIsReplacedBeforeTheMessageGoes() async throws {
        let (client, transports) = client([
            (login + ["-- dropped"]).joined(separator: "\n"),
            (login + message).joined(separator: "\n"),
        ])
        await client.prepare()
        try await client.send(envelope)
        #expect(await transports[1].isClosed, "sent on a new connection")
    }

    @Test func aPreparedConnectionLostAfterTheMessageWentIsNotSentAgain() async throws {
        let upToTheMessage = message.prefix { !$0.hasPrefix("S: 250 Message accepted") }
        let (client, _) = client([(login + upToTheMessage + ["-- dropped"]).joined(separator: "\n")])
        await client.prepare()
        await #expect(throws: (any Error).self) { try await client.send(self.envelope) }
    }

    @Test func aRecipientTheServerRefusesIsNotTriedOnASecondConnection() async throws {
        let refused = Array(message.prefix(2)) + ["C: RCPT TO:<noa@example.com>", "S: 550 No such user"]
        let (client, _) = client([(login + refused).joined(separator: "\n")])
        await client.prepare()
        await #expect(throws: SMTPError.refused(SMTPReply(code: 550, lines: ["No such user"]))) {
            try await client.send(self.envelope)
        }
    }

    @Test func aServerThatPipelinesGetsTheEnvelopeInOneWrite() async throws {
        let pipelining = login.map {
            $0 == "S: 250 AUTH PLAIN LOGIN" ? "S: 250-AUTH PLAIN LOGIN\nS: 250 PIPELINING" : $0
        }
        let envelopeCommands = [
            "MAIL FROM:<dana@icloud.com>", "RCPT TO:<noa@example.com>", "RCPT TO:<avi@example.com>",
            "RCPT TO:<boss@example.com>", "RCPT TO:<secret@example.com>", "DATA",
        ]
        let replies = ["S: 250 OK", "S: 250 OK", "S: 250 OK", "S: 250 OK", "S: 250 OK", "S: 354 Go ahead"]
        let rest = message.drop { !$0.hasPrefix("S: 354") }.dropFirst()
        let transcript =
            pipelining + ["C: " + envelopeCommands.joined(separator: "\\r\\n")] + replies + rest
        let (client, _) = client([transcript.joined(separator: "\n")])
        try await client.send(envelope)
    }
}
