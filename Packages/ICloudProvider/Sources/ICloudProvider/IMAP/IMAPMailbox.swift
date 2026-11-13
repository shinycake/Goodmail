import Foundation

/// A mailbox as `LIST` names it.
struct IMAPMailbox: Equatable, Sendable {
    /// What a mailbox is for, from its special-use attribute (RFC 6154), or for INBOX its name.
    enum Role: Equatable, Sendable {
        case inbox, sent, drafts, trash, junk, archive
    }

    /// The name commands use: modified UTF-7, with the hierarchy delimiter.
    var wireName: String
    /// The name as people read it.
    var name: String
    var role: Role?
    /// `\Noselect` and `\NonExistent` mailboxes only hold other mailboxes.
    var isSelectable: Bool

    /// From `* LIST (\HasNoChildren \Sent) "/" "Sent Messages"`.
    init?(listResponse values: [IMAPValue]) {
        guard values.count == 4, values[0].atom?.uppercased() == "LIST", let attributes = values[1].list,
            let wireBytes = values[3].bytes
        else { return nil }
        let flags = Set(attributes.compactMap { $0.atom?.lowercased() })
        wireName = String(decoding: wireBytes, as: UTF8.self)
        name = ModifiedUTF7.decode(wireName)
        isSelectable = flags.isDisjoint(with: [#"\noselect"#, #"\nonexistent"#])
        role =
            wireName.uppercased() == "INBOX"
            ? .inbox : Self.roles.first { flags.contains($0.attribute) }?.role
    }

    private static let roles: [(attribute: String, role: Role)] = [
        (#"\sent"#, .sent), (#"\drafts"#, .drafts), (#"\trash"#, .trash), (#"\junk"#, .junk),
        (#"\archive"#, .archive),
    ]
}

/// The mailbox `SELECT` opened, and what it reported about it.
struct IMAPSelection: Equatable, Sendable {
    var mailbox: String
    /// UIDs are only comparable while this stays the same (RFC 3501 §2.3.1.1).
    var uidValidity: UInt32
    /// The UID the next message will get, when the server says.
    var uidNext: UInt32?
    var messageCount: Int
    /// The mailbox's highest modification sequence, when the server supports CONDSTORE (RFC 7162).
    var highestModSeq: UInt64?

    init(mailbox: String, reply: IMAPReply) throws {
        self.mailbox = mailbox
        let codes = reply.statuses + [reply.completion]
        func code(_ name: String) -> String? { codes.lazy.compactMap { $0.code(name)?.first?.atom }.first }
        guard let uidValidity = code("UIDVALIDITY").flatMap({ UInt32($0) }) else {
            throw IMAPError.invalid(reply.completion)
        }
        self.uidValidity = uidValidity
        uidNext = code("UIDNEXT").flatMap { UInt32($0) }
        highestModSeq = code("HIGHESTMODSEQ").flatMap { UInt64($0) }
        messageCount =
            reply.data.lazy.compactMap { values -> Int? in
                guard values.count == 2, values[1].atom?.uppercased() == "EXISTS" else { return nil }
                return values[0].number.map(Int.init)
            }.last ?? 0
    }
}
