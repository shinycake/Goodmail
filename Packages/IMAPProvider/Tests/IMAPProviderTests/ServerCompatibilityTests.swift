import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// Servers that lack what iCloud has: CONDSTORE, MOVE, UIDPLUS, special-use attributes and SMTP's AUTH PLAIN.
struct ServerCompatibilityTests {
    private func connection(_ capabilities: String, _ transcript: String) async throws -> IMAPConnection {
        let transport = ScriptedTransport(
            transcript: "S: * PREAUTH [CAPABILITY IMAP4rev1 \(capabilities)] ready\n" + transcript)
        return try await IMAPConnection(transport: transport, security: .tls)
    }

    @Test func statusAsksForHIGHESTMODSEQOnlyWithCONDSTORE() async throws {
        let connection = try await connection(
            "UIDPLUS",
            """
            C: A1 STATUS "INBOX" (MESSAGES UIDNEXT UIDVALIDITY)
            S: * STATUS "INBOX" (MESSAGES 3 UIDNEXT 9 UIDVALIDITY 4)
            S: A1 OK
            """)
        #expect(
            try await connection.status(of: "INBOX")
                == IMAPFolderStatus(uidValidity: 4, uidNext: 9, messageCount: 3, highestModSeq: nil))
    }

    /// A CONDSTORE server's mailbox that keeps no mod-sequences says HIGHESTMODSEQ 0 to STATUS (RFC 7162 §3.1.3):
    /// nothing would ever count as changed after 0, so it has none.
    @Test func aMailboxWithoutModSeqsHasNone() async throws {
        let connection = try await connection(
            "CONDSTORE",
            """
            C: A1 STATUS "Notes" (MESSAGES UIDNEXT UIDVALIDITY HIGHESTMODSEQ)
            S: * STATUS "Notes" (MESSAGES 3 UIDNEXT 9 UIDVALIDITY 4 HIGHESTMODSEQ 0)
            S: A1 OK
            """)
        #expect(
            try await connection.status(of: "Notes")
                == IMAPFolderStatus(uidValidity: 4, uidNext: 9, messageCount: 3, highestModSeq: nil))
    }

    @Test func aServerWithoutMOVECopiesThenExpunges() async throws {
        let connection = try await connection(
            "UIDPLUS",
            """
            C: A1 SELECT "INBOX"
            S: * OK [UIDVALIDITY 7] ok
            S: A1 OK
            C: A2 UID MOVE 3:4 "Archive"
            S: A2 BAD Unknown command
            C: A3 UID COPY 3:4 "Archive"
            S: A3 OK [COPYUID 9 3:4 20:21] done
            C: A4 UID STORE 3:4 +FLAGS.SILENT (\\Deleted)
            S: A4 OK
            C: A5 UID EXPUNGE 3:4
            S: A5 OK
            """)
        try await connection.select("INBOX")
        let copy = try await connection.transfer([3, 4], to: "Archive", move: true)
        #expect(copy?.uidValidity == 9)
        #expect(copy?.uids == [3: 20, 4: 21])
    }

    @Test func aServerThatAdvertisesMOVEKeepsItsError() async throws {
        let connection = try await connection(
            "MOVE",
            """
            C: A1 SELECT "INBOX"
            S: * OK [UIDVALIDITY 7] ok
            S: A1 OK
            C: A2 UID MOVE 3 "Gone"
            S: A2 BAD No such mailbox
            """)
        try await connection.select("INBOX")
        await #expect(throws: IMAPError.self) { try await connection.transfer([3], to: "Gone", move: true) }
    }

    @Test func withoutUIDPLUSExpungeRemovesTheMailboxsDeletedMessages() async throws {
        let connection = try await connection(
            "",
            """
            C: A1 SELECT "Trash"
            S: * OK [UIDVALIDITY 7] ok
            S: A1 OK
            C: A2 UID STORE 5 +FLAGS.SILENT (\\Deleted)
            S: A2 OK
            C: A3 EXPUNGE
            S: * 1 EXPUNGE
            S: A3 OK
            """)
        try await connection.select("Trash")
        try await connection.expunge([5])
    }

    @Test func smtpLogsInWithLOGINWhereThatsAllTheServerOffers() async throws {
        #expect(SMTPAuthentication(features: ["AUTH GSSAPI NTLM LOGIN"]) == .login)
        #expect(SMTPAuthentication(features: ["AUTH=LOGIN"]) == .login)
        #expect(SMTPAuthentication(features: ["AUTH LOGIN PLAIN"]) == .plain)
        #expect(SMTPAuthentication(features: []) == .plain)

        let envelope = try #require(SMTPEnvelope(Data("From: dana@example.com\r\nTo: noa@example.com\r\n\r\nhi".utf8)))
        let transport = ScriptedTransport(
            transcript: """
                S: 220 mail.example.com Microsoft ESMTP MAIL Service ready
                C: EHLO goodmail.app
                S: 250-mail.example.com Hello
                S: 250-AUTH GSSAPI NTLM LOGIN
                S: 250 8BITMIME
                C: AUTH LOGIN
                S: 334 VXNlcm5hbWU6
                C: ZGFuYUBpY2xvdWQuY29t
                S: 334 UGFzc3dvcmQ6
                C: YWJjZC1lZmdoLWlqa2wtbW5vcA==
                S: 235 2.7.0 Authentication successful
                C: MAIL FROM:<dana@example.com>
                S: 250 OK
                C: RCPT TO:<noa@example.com>
                S: 250 OK
                C: DATA
                S: 354 Go
                C: From: dana@example.com\\r\\nTo: noa@example.com\\r\\n\\r\\nhi\\r\\n.
                S: 250 Queued
                C: QUIT
                S: 221 Bye
                """)
        try await SMTPClient(credentials: IMAPClientTests.credentials, security: .tls) { transport }.send(envelope)
    }
}
