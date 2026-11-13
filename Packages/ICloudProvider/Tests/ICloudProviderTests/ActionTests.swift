import Foundation
import MailCore
import Testing

@testable import ICloudProvider

struct CopyPlanTests {
    private func plan(_ action: ThreadAction, in folder: String?, flags: Set<String> = [#"\Seen"#]) -> CopyPlan {
        CopyPlan(action: action, folderLabel: folder, flags: flags)
    }

    @Test func starAndReadAreFlags() {
        #expect(plan(.star(true), in: "INBOX") == CopyPlan(addFlags: [#"\Flagged"#]))
        #expect(
            plan(.star(false), in: "INBOX", flags: [#"\Seen"#, #"\Flagged"#]) == CopyPlan(removeFlags: [#"\Flagged"#]))
        #expect(plan(.markRead(true), in: "INBOX", flags: []) == CopyPlan(addFlags: [#"\Seen"#]))
        #expect(plan(.markRead(false), in: "INBOX") == CopyPlan(removeFlags: [#"\Seen"#]))
        #expect(plan(.markRead(true), in: "INBOX") == CopyPlan(), "replaying changes nothing")
    }

    @Test func foldersBecomeMoves() {
        #expect(plan(.archive, in: "INBOX").placement == .move(toLabel: nil))
        #expect(plan(.archive, in: nil).placement == .stay)
        #expect(plan(.trash, in: "INBOX").placement == .move(toLabel: "TRASH"))
        #expect(plan(.untrash, in: "TRASH").placement == .move(toLabel: nil))
        #expect(plan(.reportSpam, in: "INBOX").placement == .move(toLabel: "SPAM"))
        #expect(plan(.moveToInbox, in: "SPAM").placement == .move(toLabel: "INBOX"))
        #expect(plan(.move(to: .label("Work"), from: .inbox), in: "INBOX").placement == .move(toLabel: "Work"))
        #expect(plan(.move(to: .inbox, from: .trash), in: "TRASH").placement == .move(toLabel: "INBOX"))
    }

    @Test func addingALabelFilesACopy() {
        let label = plan(.modifyLabels(add: ["Work"], remove: []), in: "INBOX")
        #expect(label == CopyPlan(copies: ["Work"]))
        #expect(plan(.modifyLabels(add: [], remove: ["Work"]), in: "Work").placement == .move(toLabel: nil))
    }

    @Test func sentMailOnlyMovesToTrash() {
        #expect(plan(.archive, in: "SENT") == CopyPlan())
        #expect(plan(.reportSpam, in: "SENT") == CopyPlan())
        #expect(plan(.move(to: .label("Work"), from: .inbox), in: "SENT") == CopyPlan())
        #expect(plan(.trash, in: "SENT").placement == .move(toLabel: "TRASH"))
        #expect(plan(.trash, in: "DRAFT").placement == .move(toLabel: "TRASH"))
    }
}

struct ICloudActionTests {
    @Test func archivingMovesTheInboxCopiesAndKeepsTheIndexCurrent() async throws {
        let inbox = { (uid: UInt32) in MessageKey(folder: "INBOX", uidValidity: 7, uid: uid).rawValue }
        let sent = MessageKey(folder: "Sent Messages", uidValidity: 9, uid: 3).rawValue
        let index = MemoryIndex([
            MessageIndexEntry(key: inbox(40), threadID: "a0@x", internetMessageID: "a0@x"),
            MessageIndexEntry(key: inbox(41), threadID: "a0@x", internetMessageID: "a2@x"),
            MessageIndexEntry(key: sent, threadID: "a0@x", internetMessageID: "s1@x"),
        ])
        let client = ICloudClientTests.client(
            [
                ICloudClientTests.login,
                ICloudClientTests.select("INBOX", tag: 4),
                "C: A5 UID FETCH 40:41 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)",
                ICloudClientTests.header(uid: 40, date: "1-Nov-2026 09:00:00 +0000", subject: "a", messageID: "a0@x"),
                ICloudClientTests.header(
                    uid: 41, flags: "", date: "2-Nov-2026 09:00:00 +0000", subject: "b", messageID: "a2@x"),
                "S: A5 OK",
                "C: A6 UID STORE 41 +FLAGS.SILENT (\\Seen)",
                "S: A6 OK",
                "C: A7 UID MOVE 40:41 \"Archive\"",
                "S: * OK [COPYUID 5 40:41 100:101] Moved",
                "S: * 1 EXPUNGE",
                "S: * 1 EXPUNGE",
                "S: A7 OK Move completed",
                ICloudClientTests.select("Sent Messages", tag: 8, uidValidity: 9),
                "C: A9 UID FETCH 3 (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)",
                ICloudClientTests.header(uid: 3, date: "1-Nov-2026 12:00:00 +0000", subject: "s", messageID: "s1@x"),
                "S: A9 OK",
            ].joined(separator: "\n"),
            index: index)

        try await client.perform(.modifyLabels(add: [], remove: ["INBOX", "UNREAD"]), onThread: "a0@x")

        #expect(
            index.all.map(\.key) == [
                MessageKey(folder: "Archive", uidValidity: 5, uid: 100).rawValue,
                MessageKey(folder: "Archive", uidValidity: 5, uid: 101).rawValue,
                sent,
            ])
        #expect(index.all.map(\.internetMessageID) == ["a0@x", "a2@x", "s1@x"])
    }

    @Test func addingALabelTwiceFilesOneCopy() async throws {
        let work = "&BeIF0QXVBdMF1A-"
        let index = MemoryIndex([
            MessageIndexEntry(
                key: MessageKey(folder: "INBOX", uidValidity: 7, uid: 40).rawValue, threadID: "a0@x",
                internetMessageID: "a0@x"),
            MessageIndexEntry(
                key: MessageKey(folder: work, uidValidity: 3, uid: 5).rawValue, threadID: "a0@x",
                internetMessageID: "a0@x"),
        ])
        let fetch = { (tag: Int, uid: UInt32) in
            "C: A\(tag) UID FETCH \(uid) (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)\n"
                + ICloudClientTests.header(
                    uid: uid, date: "1-Nov-2026 09:00:00 +0000", subject: "a", messageID: "a0@x")
                + "\nS: A\(tag) OK"
        }
        let client = ICloudClientTests.client(
            [
                ICloudClientTests.login,
                ICloudClientTests.select(work, tag: 4, uidValidity: 3), fetch(5, 5),
                ICloudClientTests.select("INBOX", tag: 6), fetch(7, 40),
            ].joined(separator: "\n"),
            index: index)

        try await client.perform(.modifyLabels(add: [work], remove: []), onThread: "a0@x")

        #expect(index.all.count == 2, "the Work folder already holds the message, so nothing is copied")
    }

    @Test func aCopyMovingWhereTheMessageIsAlreadyFiledIsRemoved() async throws {
        let trashKey = MessageKey(folder: "Deleted Messages", uidValidity: 2, uid: 9).rawValue
        let index = MemoryIndex([
            MessageIndexEntry(
                key: MessageKey(folder: "INBOX", uidValidity: 7, uid: 40).rawValue, threadID: "a0@x",
                internetMessageID: "a0@x"),
            MessageIndexEntry(key: trashKey, threadID: "a0@x", internetMessageID: "a0@x"),
        ])
        let fetch = { (tag: Int, uid: UInt32) in
            "C: A\(tag) UID FETCH \(uid) (UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] BODY.PEEK[TEXT]<0.2048>)\n"
                + ICloudClientTests.header(
                    uid: uid, date: "1-Nov-2026 09:00:00 +0000", subject: "a", messageID: "a0@x")
                + "\nS: A\(tag) OK"
        }
        let client = ICloudClientTests.client(
            [
                ICloudClientTests.login,
                ICloudClientTests.select("Deleted Messages", tag: 4, uidValidity: 2), fetch(5, 9),
                ICloudClientTests.select("INBOX", tag: 6), fetch(7, 40),
                #"C: A8 UID STORE 40 +FLAGS.SILENT (\Deleted)"#, "S: A8 OK",
                "C: A9 UID EXPUNGE 40", "S: A9 OK",
            ].joined(separator: "\n"),
            index: index)

        try await client.perform(.trash, onThread: "a0@x")

        #expect(index.all.map(\.key) == [trashKey])
    }

    @Test func aThreadTheIndexDoesntKnowIsNotFound() async throws {
        let client = ICloudClientTests.client(ICloudClientTests.login, index: MemoryIndex())
        await #expect(throws: ProviderError.notFound) { try await client.perform(.trash, onThread: "gone@x") }
    }
}
