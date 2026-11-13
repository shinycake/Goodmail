import Foundation
import MailCore
import Testing

@testable import ICloudProvider

struct ICloudClientTests {
    static let account = AccountID(rawValue: "icloud")

    /// Connecting and logging in, as every session starts, the way iCloud answers: capabilities only to an explicit
    /// CAPABILITY, ENABLE without `* ENABLED`, and special-use attributes only on Sent and Trash.
    static let login = #"""
        S: * OK [CAPABILITY IMAP4rev1 SASL-IR AUTH=PLAIN] iCloud IMAP ready
        C: A1 LOGIN "dana@icloud.com" "abcd-efgh-ijkl-mnop"
        S: A1 OK [CAPABILITY IMAP4rev1 SASL-IR AUTH=PLAIN] authenticated
        C: A2 CAPABILITY
        S: * CAPABILITY IMAP4rev1 CONDSTORE QRESYNC UIDPLUS ENABLE IDLE ESEARCH LIST-STATUS
        S: A2 OK CAPABILITY completed
        C: A3 ENABLE QRESYNC
        S: A3 OK ENABLE completed
        C: A4 LIST "" "*"
        S: * LIST (\HasNoChildren) "/" "INBOX"
        S: * LIST (\HasNoChildren \Sent) "/" "Sent Messages"
        S: * LIST (\HasNoChildren \Trash) "/" "Deleted Messages"
        S: * LIST (\HasNoChildren) "/" "Junk"
        S: * LIST (\HasNoChildren) "/" "Drafts"
        S: * LIST (\HasNoChildren) "/" "Archive"
        S: * LIST (\Noselect \HasChildren) "/" "Projects"
        S: * LIST (\HasNoChildren) "/" "&BeIF0QXVBdMF1A-"
        S: A4 OK LIST completed
        """#

    static func select(_ mailbox: String, tag: Int, uidValidity: UInt32 = 7, exists: Int = 2) -> String {
        """
        C: A\(tag) SELECT "\(mailbox)"
        S: * \(exists) EXISTS
        S: * OK [UIDVALIDITY \(uidValidity)] UIDs valid.
        S: * OK [UIDNEXT 50] Predicted next UID.
        S: A\(tag) OK [READ-WRITE] SELECT completed
        """
    }

    /// One message's line of a header FETCH.
    static func header(
        uid: UInt32, flags: String = #"\Seen"#, date: String, subject: String, from: String = "dana",
        inReplyTo: String? = nil, messageID: String, references: [String] = []
    ) -> String {
        let referencesHeader =
            references.isEmpty ? "" : "References: \(references.map { "<\($0)>" }.joined(separator: " "))\\r\\n"
        let literal = referencesHeader.replacing("\\r\\n", with: "\r\n") + "\r\n"
        let replyTo = inReplyTo.map { "\"<\($0)>\"" } ?? "NIL"
        return
            #"S: * \#(uid) FETCH (UID \#(uid) FLAGS (\#(flags)) INTERNALDATE "\#(date)" ENVELOPE (NIL "\#(subject)" (("\#(from)" NIL "\#(from)" "example.com")) NIL NIL NIL NIL NIL \#(replyTo) "<\#(messageID)>") BODY[HEADER.FIELDS (REFERENCES)] {\#(literal.utf8.count)}\r\n\#(referencesHeader)\r\n)"#
    }

    static let credentials = ICloudCredentials(user: "dana@icloud.com", password: "abcd-efgh-ijkl-mnop")

    static func client(
        _ transcripts: String..., smtp: String = "", index: MemoryIndex, pageSize: Int = 50
    ) -> ICloudClient {
        let transports = Transports(transcripts.map { ScriptedTransport(transcript: $0) })
        let session = IMAPSession(credentials: credentials) { try await transports.next() }
        let smtpTransport = ScriptedTransport(transcript: smtp)
        return ICloudClient(
            accountID: account, session: session, smtp: SMTPClient(credentials: credentials) { smtpTransport },
            index: index, pageSize: pageSize)
    }

    @Test func foldersBecomeLabels() async throws {
        let client = Self.client(Self.login, index: MemoryIndex())
        let labels = try await client.labels()
        #expect(
            labels.map(\.id) == ["INBOX", "SENT", "TRASH", "SPAM", "DRAFT", "&BeIF0QXVBdMF1A-", "STARRED", "UNREAD"])
        #expect(labels.first { $0.kind == .user }?.name == "עבודה")
        #expect(labels.filter { $0.kind == .user }.count == 1, "Archive is no label, and Projects holds no mail")
    }

    @Test func aPageGroupsRepliesWithTheirThreadInEveryFolder() async throws {
        // The Sent reply was read before, so the index knows it.
        let sentKey = MessageKey(folder: "Sent Messages", uidValidity: 9, uid: 3).rawValue
        let index = MemoryIndex([
            MessageIndexEntry(key: sentKey, threadID: "a0@example.com", internetMessageID: "s1@icloud.com")
        ])
        let client = Self.client(
            Self.login + "\n" + Self.select("INBOX", tag: 5) + #"""

                C: A6 UID SEARCH SINCE 31-Oct-2026
                S: * SEARCH 40 41 42
                S: A6 OK SEARCH completed
                C: A7 UID FETCH 40:42 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)
                """# + "\n"
                + [
                    Self.header(
                        uid: 40, date: "1-Nov-2026 09:00:00 +0000", subject: "Lunch", messageID: "a0@example.com"),
                    Self.header(
                        uid: 41, flags: "", date: "2-Nov-2026 09:00:00 +0000", subject: "Re: Lunch", from: "noa",
                        inReplyTo: "s1@icloud.com", messageID: "a2@example.com",
                        references: ["a0@example.com", "s1@icloud.com"]),
                    Self.header(
                        uid: 42, flags: #"\Seen \Flagged"#, date: "3-Nov-2026 09:00:00 +0000", subject: "Re: Hi",
                        inReplyTo: "b0@example.com", messageID: "b1@example.com"),
                ].joined(separator: "\n") + "\n" + "S: A7 OK FETCH completed\n"
                + Self.select("Sent Messages", tag: 8, uidValidity: 9) + "\n"
                + "C: A9 UID FETCH 3 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)\n"
                + Self.header(
                    uid: 3, date: "1-Nov-2026 12:00:00 +0000", subject: "Re: Lunch", from: "me",
                    inReplyTo: "a0@example.com", messageID: "s1@icloud.com", references: ["a0@example.com"])
                + "\nS: A9 OK FETCH completed",
            index: index)

        let page = try await client.threads(
            matching: ThreadQuery(label: "INBOX", since: Date(timeIntervalSince1970: 1_793_491_200)), pageToken: nil)

        #expect(page.nextPageToken == nil)
        #expect(page.threads.map(\.id.threadID) == ["b0@example.com", "a0@example.com"])
        let lunch = try #require(page.threads.last)
        #expect(lunch.messageCount == 3)
        #expect(lunch.subject == "Lunch")
        #expect(lunch.sender.address == "noa@example.com")
        #expect(lunch.isUnread)
        #expect(lunch.labelIDs == ["INBOX", "SENT", "UNREAD"])
        let hi = try #require(page.threads.first)
        #expect(hi.labelIDs == ["INBOX", "STARRED"], "a reply whose parent isn't known threads on the parent's ID")
        #expect(
            index.all.map(\.threadID).sorted()
                == ["a0@example.com", "a0@example.com", "a0@example.com", "b0@example.com"])
    }

    @Test func pagesWalkEachFolderNewestFirst() async throws {
        let index = MemoryIndex()
        let first = Self.client(
            Self.login + "\n" + Self.select("INBOX", tag: 5) + """

                C: A6 UID SEARCH ALL
                S: * SEARCH 10 11 12
                S: A6 OK SEARCH completed
                C: A7 UID FETCH 11:12 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)
                \(Self.header(uid: 11, date: "1-Nov-2026 09:00:00 +0000", subject: "b", messageID: "b@x"))
                \(Self.header(uid: 12, date: "2-Nov-2026 09:00:00 +0000", subject: "c", messageID: "c@x"))
                S: A7 OK FETCH completed
                """, index: index, pageSize: 2)
        let page = try await first.threads(matching: ThreadQuery(), pageToken: nil)
        #expect(page.threads.map(\.subject) == ["c", "b"])
        let token = try #require(page.nextPageToken)

        let second = Self.client(
            Self.login + "\n" + Self.select("INBOX", tag: 5) + """

                C: A6 UID SEARCH UID 1:10
                S: * SEARCH 10
                S: A6 OK SEARCH completed
                C: A7 UID FETCH 10 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)
                \(Self.header(uid: 10, date: "1-Oct-2026 09:00:00 +0000", subject: "a", messageID: "a@x"))
                S: A7 OK FETCH completed
                """, index: index, pageSize: 2)
        let next = try await second.threads(matching: ThreadQuery(), pageToken: token)
        #expect(next.threads.map(\.subject) == ["a"])
        let after = try #require(next.nextPageToken)
        #expect(try ICloudPageToken(after) == ICloudPageToken(folder: 1, position: nil), "then the Sent folder")
    }

    @Test func changesNameTheThreadsOfNewChangedAndExpungedMessages() async throws {
        let key = { (uid: UInt32) in MessageKey(folder: "INBOX", uidValidity: 7, uid: uid).rawValue }
        let index = MemoryIndex([
            MessageIndexEntry(key: key(30), threadID: "gone@x", internetMessageID: "gone@x"),
            MessageIndexEntry(key: key(31), threadID: "flag@x", internetMessageID: "flag@x"),
        ])
        let unchanged = IMAPFolderStatus(uidValidity: 9, uidNext: 4, messageCount: 1, highestModSeq: 5)
        var folders = Dictionary(
            uniqueKeysWithValues: [
                "Sent Messages", "Deleted Messages", "Junk", "Drafts", "Archive", "&BeIF0QXVBdMF1A-",
            ].map {
                ($0, unchanged)
            })
        folders["INBOX"] = IMAPFolderStatus(uidValidity: 7, uidNext: 32, messageCount: 2, highestModSeq: 100)
        let cursor = ICloudCursor(folders: folders).rawValue
        let status = { (tag: Int, name: String, line: String) in
            "C: A\(tag) STATUS \"\(name)\" (MESSAGES UIDNEXT UIDVALIDITY HIGHESTMODSEQ)\nS: * STATUS \"\(name)\" (\(line))\nS: A\(tag) OK"
        }
        let unchangedLine = "MESSAGES 1 UIDNEXT 4 UIDVALIDITY 9 HIGHESTMODSEQ 5"
        let client = Self.client(
            [
                Self.login,
                status(5, "INBOX", "MESSAGES 2 UIDNEXT 33 UIDVALIDITY 7 HIGHESTMODSEQ 104"),
                Self.select("INBOX", tag: 6),
                """
                C: A7 UID SEARCH UID 32:*
                S: * SEARCH 32
                S: A7 OK
                C: A8 UID FETCH 1:* (UID FLAGS) (CHANGEDSINCE 100 VANISHED)
                S: * VANISHED (EARLIER) 30
                S: * 2 FETCH (UID 31 FLAGS (\\Seen \\Flagged) MODSEQ (103))
                S: * 3 FETCH (UID 32 FLAGS () MODSEQ (104))
                S: A8 OK
                C: A9 UID FETCH 31:32 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)
                """,
                Self.header(uid: 31, date: "1-Nov-2026 09:00:00 +0000", subject: "f", messageID: "flag@x"),
                Self.header(
                    uid: 32, flags: "", date: "4-Nov-2026 09:00:00 +0000", subject: "n", messageID: "new@x"),
                "S: A9 OK",
                status(10, "Sent Messages", unchangedLine),
                status(11, "Deleted Messages", unchangedLine),
                status(12, "Junk", unchangedLine),
                status(13, "Drafts", unchangedLine),
                status(14, "Archive", unchangedLine),
                status(15, "&BeIF0QXVBdMF1A-", unchangedLine),
            ].joined(separator: "\n"),
            index: index)

        let changes = try await client.changes(since: cursor)

        #expect(changes.threadIDs == ["gone@x", "flag@x", "new@x"])
        #expect(index.all.map(\.threadID) == ["flag@x", "new@x"], "the expunged message leaves the index")
        let next = try ICloudCursor(changes.cursor)
        #expect(
            next.folders["INBOX"] == IMAPFolderStatus(uidValidity: 7, uidNext: 33, messageCount: 2, highestModSeq: 104))
    }

    @Test func aChangedFolderListOrUIDValidityExpiresTheCursor() async throws {
        let status = IMAPFolderStatus(uidValidity: 7, uidNext: 1, messageCount: 0, highestModSeq: 1)
        let onlyInbox = ICloudCursor(folders: ["INBOX": status])
        await #expect(throws: ProviderError.cursorExpired) {
            try await Self.client(Self.login, index: MemoryIndex()).changes(since: onlyInbox.rawValue)
        }
        await #expect(throws: ProviderError.cursorExpired) {
            try await Self.client(Self.login, index: MemoryIndex()).changes(since: "not a cursor")
        }

        let names = ["INBOX", "Sent Messages", "Deleted Messages", "Junk", "Drafts", "Archive", "&BeIF0QXVBdMF1A-"]
        let everyFolder = ICloudCursor(folders: Dictionary(uniqueKeysWithValues: names.map { ($0, status) }))
        let rebuilt = """
            C: A5 STATUS "INBOX" (MESSAGES UIDNEXT UIDVALIDITY HIGHESTMODSEQ)
            S: * STATUS "INBOX" (MESSAGES 0 UIDNEXT 1 UIDVALIDITY 8 HIGHESTMODSEQ 1)
            S: A5 OK
            """
        await #expect(throws: ProviderError.cursorExpired) {
            try await Self.client(Self.login + "\n" + rebuilt, index: MemoryIndex()).changes(
                since: everyFolder.rawValue)
        }
    }

    @Test func messagesAreReadWholeFromEveryFolder() async throws {
        let raw = [
            "From: Dana <dana@example.com>", "To: me@icloud.com", "Subject: =?UTF-8?B?16nXnNeV150=?=",
            "Message-ID: <a0@example.com>", "Content-Type: text/plain; charset=utf-8", "", "Lunch at noon?",
        ].joined(separator: "\r\n")
        let index = MemoryIndex([
            MessageIndexEntry(
                key: MessageKey(folder: "INBOX", uidValidity: 7, uid: 40).rawValue, threadID: "a0@example.com")
        ])
        let client = Self.client(
            Self.login + "\n" + Self.select("INBOX", tag: 5) + """

                C: A6 UID FETCH 40 (UID FLAGS INTERNALDATE BODY.PEEK[])
                S: * 1 FETCH (UID 40 FLAGS () INTERNALDATE "1-Nov-2026 09:00:00 +0000" BODY[] {\(raw.utf8.count)}\\r\\n\(raw.replacing("\r\n", with: "\\r\\n")))
                S: A6 OK
                """, index: index)
        let messages = try await client.messages(inThread: "a0@example.com")
        let message = try #require(messages.first)
        #expect(message.subject == "שלום")
        #expect(message.from == Contact(name: "Dana", address: "dana@example.com"))
        #expect(message.body.plain == "Lunch at noon?")
        #expect(message.snippet == "Lunch at noon?")
        #expect(message.labelIDs == ["INBOX", "UNREAD"])
        #expect(message.internetMessageID == "a0@example.com")
        #expect(message.id.messageID == "INBOX\n7\n40")
    }

    @Test func aDroppedConnectionIsOpenedAgain() async throws {
        let client = Self.client(
            "S: * OK ready\nC: A1 LOGIN \"dana@icloud.com\" \"abcd-efgh-ijkl-mnop\"\nS: A1 OK ok\nC: A2 CAPABILITY\nS: * CAPABILITY IMAP4rev1\nS: A2 OK\nC: A3 LIST \"\" \"*\"\nS: * BYE idle too long",
            Self.login, index: MemoryIndex())
        #expect(try await client.labels().count == 8)
    }
}

/// Hands out one transport per connection, in order.
actor Transports {
    private var transports: [ScriptedTransport]

    init(_ transports: [ScriptedTransport]) {
        self.transports = transports
    }

    func next() throws -> ScriptedTransport {
        guard !transports.isEmpty else { throw IMAPError.closed }
        return transports.removeFirst()
    }
}
