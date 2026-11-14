import Foundation

/// One value of an IMAP response (RFC 3501 §4): an atom, a string, NIL or a parenthesized list.
enum IMAPValue: Equatable, Sendable {
    /// Atoms, numbers and flags, such as `FETCH`, `42` or `\Seen`, and section specifiers such as `BODY[TEXT]`.
    case atom(String)
    /// A quoted string or a literal: the bytes the server sent.
    case string(Data)
    case `nil`
    case list([IMAPValue])

    var atom: String? {
        guard case .atom(let atom) = self else { return nil }
        return atom
    }

    var number: UInt32? { atom.flatMap { UInt32($0) } }

    var list: [IMAPValue]? {
        guard case .list(let list) = self else { return nil }
        return list
    }

    /// A string's bytes. Servers send atoms where strings are allowed, so an atom counts; NIL has none.
    var bytes: Data? {
        switch self {
        case .string(let data): data
        case .atom(let atom): Data(atom.utf8)
        case .nil, .list: nil
        }
    }
}

/// Reads one whole response, as `IMAPFramer` cut it, into an `IMAPResponse`.
struct IMAPParser {
    struct Malformed: Error, Equatable {
        let response: String
    }

    private let bytes: [UInt8]
    private var index = 0

    private init(_ data: Data) {
        bytes = Array(data)
    }

    static func response(from data: Data) throws -> IMAPResponse {
        var parser = IMAPParser(data)
        return try parser.response()
    }

    private mutating func response() throws -> IMAPResponse {
        if peek == UInt8(ascii: "+") { return .continuation }
        let tag = try atom()
        try expect(UInt8(ascii: " "))
        if tag != "*" { return .completion(tag: tag, try status(condition: try atom())) }
        let start = index
        if let condition = IMAPStatus.Condition(rawValue: try atom().uppercased()) {
            return .status(try status(condition: condition))
        }
        index = start
        return .data(try values(until: nil))
    }

    private mutating func status(condition name: String) throws -> IMAPStatus {
        guard let condition = IMAPStatus.Condition(rawValue: name.uppercased()) else { throw malformed }
        return try status(condition: condition)
    }

    private mutating func status(condition: IMAPStatus.Condition) throws -> IMAPStatus {
        if peek == UInt8(ascii: " ") { index += 1 }
        var code: [IMAPValue] = []
        if peek == UInt8(ascii: "[") {
            index += 1
            code = try values(until: UInt8(ascii: "]"))
            try expect(UInt8(ascii: "]"))
            if peek == UInt8(ascii: " ") { index += 1 }
        }
        let end = bytes[index...].firstIndex(of: UInt8(ascii: "\r")) ?? bytes.endIndex
        let text = String(decoding: bytes[index..<end], as: UTF8.self)
        index = end
        return IMAPStatus(condition: condition, code: code, text: text)
    }

    /// Values separated by spaces, up to `terminator` (not consumed) or the end of the line.
    private mutating func values(until terminator: UInt8?) throws -> [IMAPValue] {
        var values: [IMAPValue] = []
        while let byte = peek, byte != terminator, byte != UInt8(ascii: "\r") {
            if byte == UInt8(ascii: " ") {
                index += 1
                continue
            }
            values.append(try value())
        }
        return values
    }

    private mutating func value() throws -> IMAPValue {
        switch peek {
        case UInt8(ascii: "("):
            index += 1
            let list = try values(until: UInt8(ascii: ")"))
            try expect(UInt8(ascii: ")"))
            return .list(list)
        case UInt8(ascii: "\""):
            return .string(try quoted())
        case UInt8(ascii: "{"):
            return .string(try literal())
        default:
            let atom = try atom()
            return atom.uppercased() == "NIL" ? .nil : .atom(atom)
        }
    }

    /// An atom, which may carry a bracketed section with spaces in it, as in `BODY[HEADER.FIELDS (REFERENCES)]`.
    private mutating func atom() throws -> String {
        let start = index
        var depth = 0
        while let byte = peek {
            if byte == UInt8(ascii: "[") {
                depth += 1
            } else if byte == UInt8(ascii: "]") {
                if depth == 0 { break }
                depth -= 1
            } else if depth == 0, Self.delimiters.contains(byte) {
                break
            }
            index += 1
        }
        guard index > start else { throw malformed }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private static let delimiters: Set<UInt8> = Set(" ()\"{\r\n".utf8)

    private mutating func quoted() throws -> Data {
        try expect(UInt8(ascii: "\""))
        var data = Data()
        while let byte = peek {
            index += 1
            switch byte {
            case UInt8(ascii: "\""): return data
            case UInt8(ascii: "\\"):
                guard let escaped = peek else { throw malformed }
                data.append(escaped)
                index += 1
            default: data.append(byte)
            }
        }
        throw malformed
    }

    /// `{n}` and its line break, then n bytes.
    private mutating func literal() throws -> Data {
        try expect(UInt8(ascii: "{"))
        let start = index
        while let byte = peek, byte != UInt8(ascii: "}") { index += 1 }
        let digits = String(decoding: bytes[start..<index], as: UTF8.self).trimmingCharacters(in: ["+"])
        guard let count = Int(digits) else { throw malformed }
        try expect(UInt8(ascii: "}"))
        try expect(UInt8(ascii: "\r"))
        try expect(UInt8(ascii: "\n"))
        guard index + count <= bytes.count else { throw malformed }
        defer { index += count }
        return Data(bytes[index..<index + count])
    }

    private var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func expect(_ byte: UInt8) throws {
        guard peek == byte else { throw malformed }
        index += 1
    }

    private var malformed: Malformed { Malformed(response: String(decoding: bytes, as: UTF8.self)) }
}
