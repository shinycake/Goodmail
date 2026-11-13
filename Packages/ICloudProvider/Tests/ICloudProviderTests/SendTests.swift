import Foundation
import MailCore
import Testing

@testable import ICloudProvider

struct SMTPTests {
    static let message = [
        "From: Dana <dana@icloud.com>", "To: noa@example.com, \"Levi, Avi\" <avi@example.com>",
        "Bcc: boss@example.com,", " secret@example.com", "Subject: Hi", "Message-ID: <m1@icloud.com>", "",
        ".hidden line", "bye",
    ].joined(separator: "\r\n")

    /// Submitting a message to iCloud, as Apple documents it: port 587, STARTTLS, then AUTH PLAIN.
    static let submission = #"""
        S: 220 p00-smtp.mail.me.com ESMTP
        C: EHLO goodmail.app
        S: 250-p00-smtp.mail.me.com
        S: 250-SIZE 28311552
        S: 250 STARTTLS
        C: STARTTLS
        S: 220 Ready to start TLS
        C: <TLS>
        C: EHLO goodmail.app
        S: 250-p00-smtp.mail.me.com
        S: 250 AUTH PLAIN LOGIN
        C: AUTH PLAIN AGRhbmFAaWNsb3VkLmNvbQBhYmNkLWVmZ2gtaWprbC1tbm9w
        S: 235 Authentication successful
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
        S: 354 End data with <CR><LF>.<CR><LF>
        C: From: Dana <dana@icloud.com>\r\nTo: noa@example.com, "Levi, Avi" <avi@example.com>\r\nSubject: Hi\r\nMessage-ID: <m1@icloud.com>\r\n\r\n..hidden line\r\nbye\r\n.
        S: 250 Message accepted
        C: QUIT
        S: 221 Bye
        """#

    private func client(_ transcript: String) -> SMTPClient {
        let transport = ScriptedTransport(transcript: transcript)
        return SMTPClient(credentials: ICloudClientTests.credentials) { transport }
    }

    @Test func submitsOverTLSWithoutTheBcc() async throws {
        let envelope = try #require(SMTPEnvelope(Data(Self.message.utf8)))
        #expect(
            envelope.recipients == ["noa@example.com", "avi@example.com", "boss@example.com", "secret@example.com"])
        try await client(Self.submission).send(envelope)
    }

    @Test func thePasswordNeverGoesOutInTheClear() async throws {
        let envelope = try #require(SMTPEnvelope(Data(Self.message.utf8)))
        let plain = "S: 220 hi\nC: EHLO goodmail.app\nS: 250-hi\nS: 250 AUTH PLAIN"
        await #expect(throws: SMTPError.insecure) { try await client(plain).send(envelope) }
    }

    @Test func aRejectedPasswordIsAnAuthenticationFailure() async throws {
        let envelope = try #require(SMTPEnvelope(Data(Self.message.utf8)))
        let transcript =
            Self.submission.split(separator: "\n").prefix(12).joined(separator: "\n")
            + "\nS: 535 5.7.8 Authentication credentials invalid"
        await #expect(throws: SMTPError.authenticationFailed) { try await client(transcript).send(envelope) }
    }

    @Test func dataEndsLinesWithCRLFAndDoublesLeadingDots() {
        #expect(SMTPEnvelope.dotStuffed(Data("a\n.b\r\n..c".utf8)) == Data("a\r\n..b\r\n...c\r\n".utf8))
        #expect(SMTPEnvelope(Data("To: a@b.c\r\n\r\nno sender".utf8)) == nil)
    }

    @Test func multilineRepliesAreOneReply() throws {
        var reader = SMTPReader()
        reader.append(Data("250-one\r\n250-two\r\n".utf8))
        #expect(try reader.next() == nil)
        reader.append(Data("250 three\r\n221\r\n".utf8))
        #expect(try reader.next() == SMTPReply(code: 250, lines: ["one", "two", "three"]))
        #expect(try reader.next() == SMTPReply(code: 221, lines: [""]))
    }
}

struct ICloudSendTests {
    @Test func sentMailIsFiledInSentAndIndexedInItsThread() async throws {
        let index = MemoryIndex()
        let raw = SMTPTests.message
        let client = ICloudClientTests.client(
            [
                ICloudClientTests.login,
                ICloudClientTests.select("Sent Messages", tag: 4, uidValidity: 9),
                #"C: A5 UID SEARCH HEADER Message-ID "<m1@icloud.com>""#,
                "S: * SEARCH",
                "S: A5 OK",
                #"C: A6 APPEND "Sent Messages" (\Seen) {\#(raw.utf8.count)}"#,
                "S: + Ready for literal data",
                "C: " + raw.replacing("\r\n", with: "\\r\\n"),
                "S: A6 OK [APPENDUID 9 12] APPEND completed",
            ].joined(separator: "\n"),
            smtp: SMTPTests.submission, index: index)

        try await client.send(Data(raw.utf8), inThread: "<a0@x>")

        #expect(
            index.all == [
                MessageIndexEntry(
                    key: MessageKey(folder: "Sent Messages", uidValidity: 9, uid: 12).rawValue, threadID: "<a0@x>",
                    internetMessageID: "<m1@icloud.com>")
            ])
    }

    @Test func aMessageICloudFiledItselfIsntFiledTwice() async throws {
        let index = MemoryIndex()
        let client = ICloudClientTests.client(
            [
                ICloudClientTests.login,
                ICloudClientTests.select("Sent Messages", tag: 4, uidValidity: 9),
                #"C: A5 UID SEARCH HEADER Message-ID "<m1@icloud.com>""#,
                "S: * SEARCH 12",
                "S: A5 OK",
            ].joined(separator: "\n"),
            smtp: SMTPTests.submission, index: index)
        try await client.send(Data(SMTPTests.message.utf8), inThread: nil)
        #expect(index.all.isEmpty, "the next changes(since:) indexes iCloud's copy")
    }

    @Test func savingADraftReplacesTheOldOne() async throws {
        let index = MemoryIndex([
            MessageIndexEntry(key: MessageKey(folder: "Drafts", uidValidity: 4, uid: 7).rawValue, threadID: "<d@x>")
        ])
        let raw = "From: dana@icloud.com\r\nMessage-ID: <d2@x>\r\n\r\nhi"
        let client = ICloudClientTests.client(
            [
                ICloudClientTests.login,
                #"C: A4 APPEND "Drafts" (\Draft \Seen) {\#(raw.utf8.count)}"#,
                "S: + go",
                "C: " + raw.replacing("\r\n", with: "\\r\\n"),
                "S: A4 OK [APPENDUID 4 8] APPEND completed",
                #"C: A5 LIST "" "*""#,
                #"S: * LIST (\HasNoChildren \Drafts) "/" "Drafts""#,
                "S: A5 OK",
                ICloudClientTests.select("Drafts", tag: 6, uidValidity: 4),
                #"C: A7 UID STORE 7 +FLAGS.SILENT (\Deleted)"#,
                "S: A7 OK",
                "C: A8 UID EXPUNGE 7",
                "S: * 1 EXPUNGE",
                "S: A8 OK",
            ].joined(separator: "\n"),
            index: index)

        let old = Message.ID(
            accountID: ICloudClientTests.account,
            messageID: MessageKey(folder: "Drafts", uidValidity: 4, uid: 7).rawValue)
        try await client.saveDraft(Data(raw.utf8), inThread: "<d@x>", replacing: old)

        #expect(index.all.map(\.key) == [MessageKey(folder: "Drafts", uidValidity: 4, uid: 8).rawValue])
        #expect(index.all.map(\.threadID) == ["<d@x>"])
    }
}
