import Foundation
import Testing

@testable import IMAPProvider

/// A sync's cursor is kept between launches, so cursors that earlier builds saved must read with the same tracking,
/// and the ones this build saves must read in those builds.
struct IMAPCursorTests {
    /// A cursor as earlier builds wrote it: Inbox on a CONDSTORE server, Notes without, its marks by UID and value.
    private static let saved = #"""
        {"folders":{"INBOX":{"highestModSeq":100,"messageCount":2,"uidNext":32,"uidValidity":7},\#
        "Notes":{"messageCount":3,"uidNext":13,"uidValidity":9}},"marks":{"Notes":[10,1,12,3]}}
        """#

    @Test func aSavedCursorReadsWithEachFoldersTracking() throws {
        let cursor = try IMAPCursor(Self.saved)
        #expect(
            cursor.folders == [
                "INBOX": IMAPCursor.Folder(
                    IMAPFolderStatus(uidValidity: 7, uidNext: 32, messageCount: 2, highestModSeq: 100),
                    tracking: .modSeq(100)),
                "Notes": IMAPCursor.Folder(
                    IMAPFolderStatus(uidValidity: 9, uidNext: 13, messageCount: 3, highestModSeq: nil),
                    tracking: .flagMarks([10: [.seen], 12: [.seen, .flagged]])),
            ])
        #expect(try IMAPCursor(cursor.rawValue) == cursor)
    }

    @Test func aFolderWithoutModSeqOrMarksComparesFromNothing() throws {
        let cursor = try IMAPCursor(#"{"folders":{"INBOX":{"messageCount":3,"uidNext":13,"uidValidity":7}}}"#)
        #expect(cursor.folders["INBOX"]?.tracking == .flagMarks([:]))
    }

    /// Earlier builds kept a mailbox without mod-sequences at HIGHESTMODSEQ 0, where nothing ever changed.
    @Test func aFolderSavedAtModSeqZeroComparesFlags() throws {
        let cursor = try IMAPCursor(
            #"{"folders":{"INBOX":{"highestModSeq":0,"messageCount":3,"uidNext":13,"uidValidity":7}}}"#)
        #expect(cursor.folders["INBOX"]?.tracking == .flagMarks([:]))
    }

    @Test func aCursorIsSavedAsEarlierBuildsSavedIt() {
        let cursor = IMAPCursor(folders: [
            "INBOX": IMAPCursor.Folder(
                IMAPFolderStatus(uidValidity: 7, uidNext: 32, messageCount: 2, highestModSeq: 100),
                tracking: .modSeq(100))
        ])
        #expect(
            cursor.rawValue
                == #"{"folders":{"INBOX":{"highestModSeq":100,"messageCount":2,"uidNext":32,"uidValidity":7}}}"#)
    }

    @Test func onlyAFolderTrackedByModSeqCanBeUnchanged() {
        let status = IMAPFolderStatus(uidValidity: 7, uidNext: 13, messageCount: 3, highestModSeq: 5)
        #expect(IMAPCursor.Folder(status, tracking: .modSeq(5)).isUnchanged(at: status))
        #expect(!IMAPCursor.Folder(status, tracking: .modSeq(4)).isUnchanged(at: status))
        #expect(!IMAPCursor.Folder(status, tracking: .flagMarks([:])).isUnchanged(at: status))
    }
}
