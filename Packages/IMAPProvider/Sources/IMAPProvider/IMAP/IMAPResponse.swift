import Foundation

/// One server response (RFC 3501 §7).
enum IMAPResponse: Equatable, Sendable {
    /// `+`: the server waits for the rest of a command.
    case continuation
    /// The end of a command: `A1 OK LOGIN completed`.
    case completion(tag: String, IMAPStatus)
    /// An untagged `OK`, `NO`, `BAD`, `BYE` or `PREAUTH`.
    case status(IMAPStatus)
    /// Any other untagged response, such as `* 3 EXISTS` or `* LIST (\HasNoChildren) "/" INBOX`.
    case data([IMAPValue])
}

struct IMAPStatus: Equatable, Sendable {
    enum Condition: String, Sendable {
        case ok = "OK"
        case no = "NO"
        case bad = "BAD"
        case bye = "BYE"
        case preauth = "PREAUTH"
    }

    var condition: Condition
    /// The bracketed response code, such as `[UIDVALIDITY 3857529045]`, as values.
    var code: [IMAPValue] = []
    var text: String = ""

    /// The response code's arguments when the code is `name`.
    func code(_ name: String) -> [IMAPValue]? {
        guard code.first?.atom?.uppercased() == name else { return nil }
        return Array(code.dropFirst())
    }
}

/// Cuts the server's byte stream into whole responses: a line, plus the literals it announces and the lines after
/// them.
struct IMAPFramer {
    private var buffer: [UInt8] = []

    mutating func append(_ data: Data) {
        buffer.append(contentsOf: data)
    }

    /// The next whole response, or `nil` until more bytes arrive.
    mutating func next() -> Data? {
        var position = 0
        while let lineEnd = Self.lineEnd(in: buffer, from: position) {
            guard let count = Self.literalCount(endingAt: lineEnd, in: buffer) else {
                let response = Data(buffer[..<(lineEnd + 2)])
                buffer.removeFirst(lineEnd + 2)
                return response
            }
            position = lineEnd + 2 + count
            guard position <= buffer.count else { return nil }
        }
        return nil
    }

    private static func lineEnd(in buffer: [UInt8], from start: Int) -> Int? {
        guard start < buffer.count else { return nil }
        var index = start
        while index + 1 < buffer.count {
            if buffer[index] == UInt8(ascii: "\r"), buffer[index + 1] == UInt8(ascii: "\n") { return index }
            index += 1
        }
        return nil
    }

    /// The size of the literal a line announces by ending in `{n}` or `{n+}`.
    private static func literalCount(endingAt lineEnd: Int, in buffer: [UInt8]) -> Int? {
        guard lineEnd > 0, buffer[lineEnd - 1] == UInt8(ascii: "}"),
            let open = buffer[..<lineEnd].lastIndex(of: UInt8(ascii: "{"))
        else { return nil }
        let digits = String(decoding: buffer[(open + 1)..<(lineEnd - 1)], as: UTF8.self)
        return Int(digits.trimmingCharacters(in: ["+"]))
    }
}
