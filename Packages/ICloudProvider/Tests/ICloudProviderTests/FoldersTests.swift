import Foundation
import MailCore
import Testing

@testable import ICloudProvider

struct FoldersTests {
    private func mailbox(_ name: String, attribute: String? = nil) throws -> IMAPMailbox {
        let line = #"* LIST (\HasNoChildren\#(attribute.map { " " + $0 } ?? "")) "/" "\#(name)""#
        guard case .data(let values) = try IMAPParser.response(from: Data((line + "\r\n").utf8)) else {
            throw IMAPError.closed
        }
        return try #require(IMAPMailbox(listResponse: values))
    }

    @Test func iCloudsUnmarkedFoldersTakeTheirRoleFromTheirName() throws {
        let folders = Folders([
            try mailbox("INBOX"), try mailbox("Sent Messages", attribute: #"\Sent"#),
            try mailbox("Deleted Messages", attribute: #"\Trash"#), try mailbox("Drafts"), try mailbox("Junk"),
            try mailbox("Archive"), try mailbox("Receipts"),
        ])
        #expect(folders.all.map(\.role) == [.inbox, .sent, .trash, .drafts, .junk, .archive, nil])
        #expect(folders.folder(for: SystemLabel.draft)?.wireName == "Drafts")
        #expect(folders.folder(for: nil)?.wireName == "Archive", "archiving moves to Archive")
        #expect(
            folders.search(for: nil).folders.map(\.wireName) == [
                "INBOX", "Sent Messages", "Drafts", "Archive", "Receipts",
            ])
    }

    @Test func aMarkedFolderKeepsItsRoleOverAFolderNamedForIt() throws {
        let folders = Folders([try mailbox("Drafts"), try mailbox("Brouillons", attribute: #"\Drafts"#)])
        #expect(folders.all.map(\.role) == [nil, .drafts])
        #expect(folders.folder(for: SystemLabel.draft)?.wireName == "Brouillons")
    }
}
