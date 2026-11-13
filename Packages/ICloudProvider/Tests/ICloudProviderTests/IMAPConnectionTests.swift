import Foundation
import MailCore
import Testing

@testable import ICloudProvider

struct IMAPConnectionTests {
    /// Logging in to iCloud, listing, opening the Inbox and reading its newest headers, as the sync will.
    static let inboxSession = #"""
        S: * OK [CAPABILITY IMAP4rev1 SASL-IR AUTH=PLAIN] iCloud IMAP ready
        C: A1 LOGIN "dana@icloud.com" "abcd-efgh-ijkl-mnop"
        S: A1 OK [CAPABILITY IMAP4rev1 CONDSTORE QRESYNC IDLE UIDPLUS MOVE SPECIAL-USE] user dana@icloud.com authenticated
        C: A2 LIST "" "*"
        S: * LIST (\HasNoChildren) "/" "INBOX"
        S: * LIST (\HasNoChildren \Sent) "/" "Sent Messages"
        S: * LIST (\HasNoChildren \Trash) "/" "Deleted Messages"
        S: * LIST (\HasNoChildren \Junk) "/" "Junk"
        S: * LIST (\HasNoChildren \Drafts) "/" "Drafts"
        S: * LIST (\HasNoChildren \Archive) "/" "Archive"
        S: * LIST (\HasNoChildren) "/" "&BeIF0QXVBdMF1A-"
        S: A2 OK LIST completed
        C: A3 SELECT "INBOX"
        S: * FLAGS (\Answered \Flagged \Deleted \Seen \Draft $NotJunk)
        S: * OK [PERMANENTFLAGS (\Answered \Flagged \Deleted \Seen \Draft $NotJunk \*)] Flags permitted.
        S: * 2 EXISTS
        S: * 0 RECENT
        S: * OK [UIDVALIDITY 1729000001] UIDs valid.
        S: * OK [UIDNEXT 42] Predicted next UID.
        S: * OK [HIGHESTMODSEQ 90210] Highest
        S: A3 OK [READ-WRITE] SELECT completed
        C: A4 UID SEARCH SINCE 20-Oct-2026
        S: * SEARCH 41 40
        S: A4 OK SEARCH completed
        C: A5 UID FETCH 40:41 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES)])
        S: * 1 FETCH (UID 40 FLAGS (\Seen) INTERNALDATE "20-Oct-2026 09:14:05 +0300" ENVELOPE ("Tue, 20 Oct 2026 09:14:01 +0300" "=?UTF-8?B?16nXnNeV150=?=" (("Dana Levi" NIL "dana" "example.com")) (("Dana Levi" NIL "dana" "example.com")) NIL ((NIL NIL "me" "icloud.com")) (("Noa" NIL "noa" "example.com")) NIL NIL "<a1@example.com>") BODY[HEADER.FIELDS (REFERENCES)] {2}\r\n\r\n)
        S: * 2 FETCH (UID 41 FLAGS () INTERNALDATE " 1-Nov-2026 18:00:00 +0000" ENVELOPE (NIL "Re: Lunch" ((NIL NIL "me" "icloud.com")) NIL NIL (("Dana Levi" NIL "dana" "example.com")) NIL NIL "<a1@example.com>" "<b2@icloud.com>") BODY[HEADER.FIELDS (REFERENCES)] {51}\r\nReferences: <a0@example.com>\r\n <a1@example.com>\r\n\r\n)
        S: A5 OK FETCH completed
        C: A6 LOGOUT
        S: * BYE Logging out
        S: A6 OK LOGOUT completed
        """#

    @Test(arguments: [Int.max, 7])
    func readsTheInboxHeaders(chunkSize: Int) async throws {
        let transport = ScriptedTransport(transcript: Self.inboxSession, chunkSize: chunkSize)
        let connection = try await IMAPConnection(transport: transport)
        #expect(await connection.state == .notAuthenticated)

        try await connection.login(user: "dana@icloud.com", password: "abcd-efgh-ijkl-mnop")
        #expect(await connection.capabilities?.isSuperset(of: ["CONDSTORE", "QRESYNC", "SPECIAL-USE"]) == true)

        let mailboxes = try await connection.mailboxes()
        #expect(mailboxes.map(\.role) == [.inbox, .sent, .trash, .junk, .drafts, .archive, nil])
        #expect(mailboxes.last?.name == "עבודה")

        let selection = try await connection.select("INBOX")
        #expect(selection.uidValidity == 1_729_000_001)
        #expect(selection.uidNext == 42)
        #expect(selection.highestModSeq == 90210)
        #expect(selection.messageCount == 2)
        #expect(await connection.state == .selected(selection))

        let uids = try await connection.searchUIDs(IMAPSearch(since: Date(timeIntervalSince1970: 1_792_500_000)))
        #expect(uids == [40, 41])

        let headers = try await connection.headers(of: uids)
        #expect(headers.map(\.uid) == [40, 41])
        let first = headers[0]
        #expect(first.subject == "שלום")
        #expect(first.from == [Contact(name: "Dana Levi", address: "dana@example.com")])
        #expect(first.to == [Contact(name: nil, address: "me@icloud.com")])
        #expect(first.cc == [Contact(name: "Noa", address: "noa@example.com")])
        #expect(first.receivedAt == Date(timeIntervalSince1970: 1_792_476_845))
        #expect(first.messageID == "<a1@example.com>")
        #expect(first.references.isEmpty)
        #expect(!first.isUnread)
        let reply = headers[1]
        #expect(reply.isUnread)
        #expect(reply.inReplyTo == "<a1@example.com>")
        #expect(reply.references == ["<a0@example.com>", "<a1@example.com>"])
        #expect(reply.receivedAt == Date(timeIntervalSince1970: 1_793_556_000))

        try await connection.logout()
        #expect(await connection.state == .closed)
    }

    @Test func aRejectedPasswordIsAnAuthenticationFailure() async throws {
        let transport = ScriptedTransport(
            transcript: """
                S: * OK iCloud IMAP ready
                C: A1 LOGIN "dana@icloud.com" "wrong"
                S: A1 NO [AUTHENTICATIONFAILED] Authentication failed.
                """)
        let connection = try await IMAPConnection(transport: transport)
        await #expect(throws: IMAPError.authenticationFailed) {
            try await connection.login(user: "dana@icloud.com", password: "wrong")
        }
        #expect(await connection.state == .notAuthenticated)
    }

    @Test func commandsNeedTheirStateAndNothingIsSent() async throws {
        let transport = ScriptedTransport(transcript: "S: * OK ready")
        let connection = try await IMAPConnection(transport: transport)
        await #expect(throws: IMAPError.wrongState) { try await connection.mailboxes() }
        await #expect(throws: IMAPError.wrongState) { try await connection.headers(of: [1]) }
        #expect(await transport.sent.isEmpty)
    }

    @Test func aServerThatHangsUpClosesTheConnection() async throws {
        let transport = ScriptedTransport(
            transcript: """
                S: * PREAUTH ready
                C: A1 SELECT "INBOX"
                S: * BYE Server shutting down
                """)
        let connection = try await IMAPConnection(transport: transport)
        #expect(await connection.state == .authenticated)
        await #expect(throws: IMAPError.closed) { try await connection.select("INBOX") }
        #expect(await connection.state == .closed)
    }

    @Test func concurrentCommandsRunOneAtATime() async throws {
        let transport = ScriptedTransport(
            transcript: """
                S: * PREAUTH ready
                C: A1 LIST "" "*"
                S: * LIST () "/" INBOX
                S: A1 OK done
                C: A2 LIST "" "*"
                S: * LIST () "/" INBOX
                S: A2 OK done
                """)
        let connection = try await IMAPConnection(transport: transport)
        async let first = connection.mailboxes()
        async let second = connection.mailboxes()
        #expect(try await first.count == 1)
        #expect(try await second.count == 1)
    }

    @Test func argumentsAreQuotedAndUIDsCompressed() throws {
        #expect(
            try IMAPCommand.login(user: #"a"b"#, password: #"c\d"#).line(tag: "A9")
                == Data((#"A9 LOGIN "a\"b" "c\\d""# + "\r\n").utf8))
        #expect(throws: IMAPError.unencodable) { try IMAPCommand.select("Line\r\nBreak").line(tag: "A1") }
        #expect(IMAPCommand.sequenceSet([7, 1, 2, 3, 9, 8, 12]) == "1:3,7:9,12")
        #expect(IMAPCommand.searchDate(Date(timeIntervalSince1970: 1_792_500_000)) == "20-Oct-2026")
        #expect(IMAPCommand.uids(inSequenceSet: "41,43:45,9:8") == [41, 43, 44, 45, 8, 9])
    }

    @Test func searchesWriteEveryCriterion() {
        #expect(IMAPSearch().criteria == "ALL")
        let search = IMAPSearch(
            uids: 32...UInt32.max, since: Date(timeIntervalSince1970: 1_792_500_000),
            before: Date(timeIntervalSince1970: 1_792_600_000), flag: .unseen)
        #expect(search.criteria == "UID 32:* SINCE 20-Oct-2026 BEFORE 21-Oct-2026 UNSEEN")
        #expect(IMAPSearch(uids: 1...9).criteria == "UID 1:9")
    }
}
