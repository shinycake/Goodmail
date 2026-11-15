import Foundation
import MailCore
import Testing

@testable import IMAPProvider

/// A server without CONDSTORE can't say which messages' flags changed, so each sync compares the flags of every
/// folder's latest messages with the cursor's.
struct FlagChangesTests {
    /// Logging in to a server with neither CONDSTORE nor QRESYNC, and one folder.
    private static let login = #"""
        S: * OK mail.example.com ready
        C: A1 LOGIN "dana@icloud.com" "abcd-efgh-ijkl-mnop"
        S: A1 OK logged in
        C: A2 CAPABILITY
        S: * CAPABILITY IMAP4rev1 UIDPLUS IDLE
        S: A2 OK
        C: A3 LIST "" "*"
        S: * LIST (\HasNoChildren) "/" "INBOX"
        S: A3 OK
        """#

    private static let status = """
        C: A4 STATUS "INBOX" (MESSAGES UIDNEXT UIDVALIDITY)
        S: * STATUS "INBOX" (MESSAGES 3 UIDNEXT 13 UIDVALIDITY 7)
        S: A4 OK
        """

    private static let inbox = IMAPFolderStatus(uidValidity: 7, uidNext: 13, messageCount: 3, highestModSeq: nil)

    @Test func onlyMarksThatChangedOnBothSidesCount() {
        let old: [UInt32: FlagMarks] = [10: [.seen], 11: [], 12: [.seen, .flagged], 9: []]
        let new: [UInt32: FlagMarks] = [10: [.seen], 11: [.seen], 12: [.seen], 13: [.flagged]]
        #expect(FlagMarks.changed(from: old, to: new) == [11, 12])
        #expect(FlagMarks([#"\Seen"#, #"\Answered"#, #"\Flagged"#]) == [.seen, .flagged])
    }

    @Test func aFlagChangedInAnotherAppNamesItsThreadAndMovesTheCursorOn() async throws {
        let key = { (uid: UInt32) in MessageKey(folder: "INBOX", uidValidity: 7, uid: uid).rawValue }
        let index = MemoryIndex([
            MessageIndexEntry(key: key(10), threadID: "kept@x", internetMessageID: "kept@x"),
            MessageIndexEntry(key: key(11), threadID: "read@x", internetMessageID: "read@x"),
            MessageIndexEntry(key: key(12), threadID: "star@x", internetMessageID: "star@x"),
        ])
        let cursor = IMAPCursor(
            folders: ["INBOX": Self.inbox], marks: ["INBOX": [10: [.seen], 11: [], 12: [.seen]]])
        let client = IMAPClientTests.client(
            [
                Self.login, Self.status, IMAPClientTests.select("INBOX", tag: 5, exists: 3),
                """
                C: A6 FETCH 1:* (UID FLAGS)
                S: * 1 FETCH (UID 10 FLAGS (\\Seen))
                S: * 2 FETCH (UID 11 FLAGS (\\Seen))
                S: * 3 FETCH (UID 12 FLAGS (\\Seen \\Flagged))
                S: A6 OK
                C: A7 UID FETCH 11:12 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)
                """,
                IMAPClientTests.header(uid: 11, date: "1-Nov-2026 09:00:00 +0000", subject: "r", messageID: "read@x"),
                IMAPClientTests.header(
                    uid: 12, flags: #"\Seen \Flagged"#, date: "2-Nov-2026 09:00:00 +0000", subject: "s",
                    messageID: "star@x"),
                "S: A7 OK",
            ].joined(separator: "\n"),
            index: index)

        let changes = try await client.changes(since: cursor.rawValue)

        #expect(changes.threadIDs == ["read@x", "star@x"])
        let next = try IMAPCursor(changes.cursor)
        #expect(next.marks?["INBOX"] == [10: [.seen], 11: [.seen], 12: [.seen, .flagged]])
    }

    @Test func aCursorFromBeforeMarksTakesThemWithoutNamingAnything() async throws {
        let client = IMAPClientTests.client(
            [
                Self.login, Self.status, IMAPClientTests.select("INBOX", tag: 5, exists: 3),
                """
                C: A6 FETCH 1:* (UID FLAGS)
                S: * 1 FETCH (UID 10 FLAGS (\\Seen))
                S: A6 OK
                """,
            ].joined(separator: "\n"),
            index: MemoryIndex())

        let changes = try await client.changes(since: IMAPCursor(folders: ["INBOX": Self.inbox]).rawValue)

        #expect(changes.threadIDs.isEmpty)
        #expect(try IMAPCursor(changes.cursor).marks?["INBOX"] == [10: [.seen]])
    }

    @Test func onlyTheLatestMessagesAreCompared() async throws {
        let transport = ScriptedTransport(
            transcript: """
                S: * PREAUTH [CAPABILITY IMAP4rev1] ready
                C: A1 SELECT "INBOX"
                S: * 500 EXISTS
                S: * OK [UIDVALIDITY 7] ok
                S: A1 OK
                C: A2 FETCH 301:* (UID FLAGS)
                S: * 301 FETCH (UID 900 FLAGS ())
                S: A2 OK
                """)
        let connection = try await IMAPConnection(transport: transport, security: .tls)
        try await connection.select("INBOX")
        #expect(try await connection.flagMarks(ofLast: 200) == [900: []])
    }

    @Test func gmailsAllMailAndStarredFoldersArentFoldersOfTheirOwn() throws {
        let lines = [
            #"* LIST (\HasNoChildren) "/" "INBOX""#, #"* LIST (\HasNoChildren \All) "/" "[Gmail]/All Mail""#,
            #"* LIST (\HasNoChildren \Flagged) "/" "[Gmail]/Starred""#, #"* LIST (\HasNoChildren) "/" "Starred""#,
        ]
        let mailboxes = try lines.map { line in
            guard case .data(let values) = try IMAPParser.response(from: Data((line + "\r\n").utf8)) else {
                throw IMAPError.closed
            }
            return try #require(IMAPMailbox(listResponse: values))
        }
        #expect(Folders(mailboxes).all.map(\.wireName) == ["INBOX", "Starred"])
    }
}
