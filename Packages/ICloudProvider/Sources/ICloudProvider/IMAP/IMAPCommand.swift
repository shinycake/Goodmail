import Foundation

/// The commands Goodmail sends, each written as one line (RFC 3501 §6).
enum IMAPCommand: Equatable, Sendable {
    case capability
    case login(user: String, password: String)
    /// Every mailbox, with its special-use attributes (RFC 6154).
    case list
    /// Opens a mailbox by its name on the wire, in modified UTF-7.
    case select(String)
    /// Turns on an extension, such as QRESYNC (RFC 5161).
    case enable(String)
    /// A mailbox's counters without selecting it.
    case status(String)
    case uidSearch(IMAPSearch)
    case uidFetch(uids: [UInt32], items: String)
    /// The selected mailbox's messages whose flags changed after `modSeq` (RFC 7162 §3.1.4), and with QRESYNC
    /// enabled, the UIDs expunged since (`VANISHED`, RFC 7162 §3.2.6).
    case uidFetchChanged(sinceModSeq: UInt64, vanished: Bool)
    /// Adds or removes flags, without the server echoing them back.
    case uidStore(uids: [UInt32], flags: Set<String>, add: Bool)
    /// Files copies of messages in another mailbox; the originals stay.
    case uidCopy(uids: [UInt32], mailbox: String)
    /// Moves messages to another mailbox (RFC 6851).
    case uidMove(uids: [UInt32], mailbox: String)
    /// Removes these messages for good, once they are flagged `\Deleted` (RFC 4315 §2.1).
    case uidExpunge(uids: [UInt32])
    /// Adds a message to a mailbox. The line announces the message as a literal of `size` bytes, which follows
    /// once the server asks for it.
    case append(mailbox: String, flags: Set<String>, size: Int)
    case logout

    /// The UID, flags, dates, envelope and threading headers of a message, without marking it read.
    static let headerItems = "(UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES)])"
    /// The whole message, without marking it read.
    static let messageItems = "(UID FLAGS INTERNALDATE BODY.PEEK[])"

    /// The command's line. Throws `IMAPError.unencodable` for an argument a quoted string can't carry.
    func line(tag: String) throws -> Data {
        Data("\(tag) \(try arguments)\r\n".utf8)
    }

    private var arguments: String {
        get throws {
            switch self {
            case .capability: "CAPABILITY"
            case .login(let user, let password): "LOGIN \(try Self.quoted(user)) \(try Self.quoted(password))"
            case .list: #"LIST "" "*""#
            case .select(let mailbox): "SELECT \(try Self.quoted(mailbox))"
            case .enable(let capability): "ENABLE \(capability)"
            case .status(let mailbox): "STATUS \(try Self.quoted(mailbox)) (MESSAGES UIDNEXT UIDVALIDITY HIGHESTMODSEQ)"
            case .uidSearch(let search): "UID SEARCH \(try search.criteria)"
            case .uidFetch(let uids, let items): "UID FETCH \(Self.sequenceSet(uids)) \(items)"
            case .uidFetchChanged(let modSeq, let vanished):
                "UID FETCH 1:* (UID FLAGS) (CHANGEDSINCE \(modSeq)\(vanished ? " VANISHED" : ""))"
            case .uidStore(let uids, let flags, let add):
                "UID STORE \(Self.sequenceSet(uids)) \(add ? "+" : "-")FLAGS.SILENT (\(flags.sorted().joined(separator: " ")))"
            case .uidCopy(let uids, let mailbox): "UID COPY \(Self.sequenceSet(uids)) \(try Self.quoted(mailbox))"
            case .uidMove(let uids, let mailbox): "UID MOVE \(Self.sequenceSet(uids)) \(try Self.quoted(mailbox))"
            case .uidExpunge(let uids): "UID EXPUNGE \(Self.sequenceSet(uids))"
            case .append(let mailbox, let flags, let size):
                "APPEND \(try Self.quoted(mailbox)) (\(flags.sorted().joined(separator: " "))) {\(size)}"
            case .logout: "LOGOUT"
            }
        }
    }

    /// A quoted string (RFC 3501 §4.3). Line breaks and non-ASCII would need a literal, which nothing sends yet.
    static func quoted(_ text: String) throws -> String {
        guard text.unicodeScalars.allSatisfy({ $0.isASCII && $0 != "\r" && $0 != "\n" }) else {
            throw IMAPError.unencodable
        }
        let escaped = text.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// UIDs as ranges, such as `1:3,7`.
    static func sequenceSet(_ uids: [UInt32]) -> String {
        var ranges: [ClosedRange<UInt32>] = []
        for uid in Set(uids).sorted() {
            if let last = ranges.last, last.upperBound + 1 == uid {
                ranges[ranges.count - 1] = last.lowerBound...uid
            } else {
                ranges.append(uid...uid)
            }
        }
        return ranges.map { $0.count == 1 ? "\($0.lowerBound)" : "\($0.lowerBound):\($0.upperBound)" }
            .joined(separator: ",")
    }

    /// The UIDs `1:3,7` names. A `*` in a set the server sends can't happen in `VANISHED`, so it is skipped.
    static func uids(inSequenceSet set: String) -> [UInt32] {
        set.split(separator: ",").flatMap { range -> [UInt32] in
            let bounds = range.split(separator: ":").compactMap { UInt32($0) }
            switch bounds.count {
            case 1: return bounds
            case 2: return Array(min(bounds[0], bounds[1])...max(bounds[0], bounds[1]))
            default: return []
            }
        }
    }

    /// `1-Feb-1994`. IMAP dates have no time zone; UTC is as good as any.
    static func searchDate(_ date: Date) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(day: .defaultDigits)-\(month: .abbreviated)-\(year: .defaultDigits)",
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: .gmt,
                calendar: Calendar(identifier: .gregorian)))
    }
}
