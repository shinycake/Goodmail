import Foundation

/// Where a message lives. An IMAP UID names a message only within its mailbox and that mailbox's UIDVALIDITY
/// (RFC 3501 §2.3.1.1), so the key carries all three. Written `folder\nuidValidity\nuid`, it is the message's
/// `MessageIndexEntry.key` and its `Message.ID`.
struct MessageKey: Hashable, Sendable {
    /// The folder's wire name.
    var folder: String
    var uidValidity: UInt32
    var uid: UInt32

    init(folder: String, uidValidity: UInt32, uid: UInt32) {
        self.folder = folder
        self.uidValidity = uidValidity
        self.uid = uid
    }

    /// Commands can't carry a mailbox name with a line break (`IMAPCommand.quoted`), so the separator is unambiguous.
    init?(rawValue: String) {
        let parts = rawValue.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count == 3, let uidValidity = UInt32(parts[1]), let uid = UInt32(parts[2]) else { return nil }
        self.init(folder: String(parts[0]), uidValidity: uidValidity, uid: uid)
    }

    var rawValue: String { "\(folder)\n\(uidValidity)\n\(uid)" }
}
