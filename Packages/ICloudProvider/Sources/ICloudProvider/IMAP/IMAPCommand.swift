import Foundation

/// The commands Goodmail sends, each written as one line (RFC 3501 §6).
enum IMAPCommand: Equatable, Sendable {
    case capability
    case login(user: String, password: String)
    /// Every mailbox, with its special-use attributes (RFC 6154).
    case list
    /// Opens a mailbox by its name on the wire, in modified UTF-7.
    case select(String)
    /// The UIDs of the selected mailbox's messages received on or after the day `since` falls on.
    case uidSearch(since: Date)
    case uidFetch(uids: [UInt32], items: String)
    case logout

    /// The UID, flags, dates, envelope and threading headers of a message, without marking it read.
    static let headerItems = "(UID FLAGS INTERNALDATE ENVELOPE BODY.PEEK[HEADER.FIELDS (REFERENCES)])"

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
            case .uidSearch(let since): "UID SEARCH SINCE \(Self.searchDate(since))"
            case .uidFetch(let uids, let items): "UID FETCH \(Self.sequenceSet(uids)) \(items)"
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
