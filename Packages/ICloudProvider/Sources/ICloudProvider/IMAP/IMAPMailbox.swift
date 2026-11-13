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

/// A mailbox's counters, as `STATUS` reports them without selecting it.
struct IMAPFolderStatus: Equatable, Codable, Sendable {
    var uidValidity: UInt32
    var uidNext: UInt32
    var messageCount: Int
    /// `nil` when the server doesn't support CONDSTORE (RFC 7162).
    var highestModSeq: UInt64?

    /// From `* STATUS "INBOX" (MESSAGES 2 UIDNEXT 42 UIDVALIDITY 1729000001 HIGHESTMODSEQ 90210)`.
    init?(statusResponse values: [IMAPValue]) {
        guard values.count == 3, values[0].atom?.uppercased() == "STATUS", let list = values[2].list,
            list.count.isMultiple(of: 2)
        else { return nil }
        var counters: [String: String] = [:]
        for index in stride(from: 0, to: list.count, by: 2) {
            guard let name = list[index].atom, let value = list[index + 1].atom else { return nil }
            counters[name.uppercased()] = value
        }
        guard let uidValidity = counters["UIDVALIDITY"].flatMap({ UInt32($0) }),
            let uidNext = counters["UIDNEXT"].flatMap({ UInt32($0) }),
            let messageCount = counters["MESSAGES"].flatMap({ Int($0) })
        else { return nil }
        self.init(
            uidValidity: uidValidity, uidNext: uidNext, messageCount: messageCount,
            highestModSeq: counters["HIGHESTMODSEQ"].flatMap { UInt64($0) })
    }

    init(uidValidity: UInt32, uidNext: UInt32, messageCount: Int, highestModSeq: UInt64?) {
        self.uidValidity = uidValidity
        self.uidNext = uidNext
        self.messageCount = messageCount
        self.highestModSeq = highestModSeq
    }
}

/// Where a COPY or MOVE put the messages: `[COPYUID 38505 304,319:320 3956:3958]` (RFC 4315 §3).
struct IMAPCopy: Equatable, Sendable {
    /// The destination's UIDVALIDITY.
    var uidValidity: UInt32
    /// Each message's UID in the destination, by its UID in the source.
    var uids: [UInt32: UInt32]

    init?(status: IMAPStatus) {
        guard let values = status.code("COPYUID"), values.count == 3, let uidValidity = values[0].number,
            let sources = values[1].atom, let destinations = values[2].atom
        else { return nil }
        let from = IMAPCommand.uids(inSequenceSet: sources)
        let to = IMAPCommand.uids(inSequenceSet: destinations)
        guard from.count == to.count else { return nil }
        self.uidValidity = uidValidity
        uids = Dictionary(zip(from, to)) { first, _ in first }
    }
}

/// Where a message landed: its mailbox's UIDVALIDITY and its UID there.
struct MessageUID: Equatable, Sendable {
    var uidValidity: UInt32
    var uid: UInt32
}
