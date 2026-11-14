import Foundation

/// One server reply (RFC 5321 §4.2): a code and its text, over one line or several (`250-…` then `250 …`).
struct SMTPReply: Equatable, Sendable {
    var code: Int
    var lines: [String]

    /// 2xx: done. 3xx: go on (354 after DATA).
    var isPositive: Bool { (200..<400).contains(code) }
    /// 5xx: the server won't take this, and asking again won't change that.
    var isPermanentFailure: Bool { (500..<600).contains(code) }
}

/// Cuts the server's byte stream into whole replies.
struct SMTPReader {
    private var buffer: [UInt8] = []
    private var lines: [String] = []

    mutating func append(_ data: Data) {
        buffer.append(contentsOf: data)
    }

    /// The next whole reply, or `nil` until more bytes arrive. Throws `SMTPError.malformed` for a line without a code.
    mutating func next() throws -> SMTPReply? {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self).trimmingCharacters(in: ["\r"])
            buffer.removeFirst(newline + 1)
            guard line.count >= 3, let code = Int(line.prefix(3)) else { throw SMTPError.malformed(line) }
            lines.append(String(line.dropFirst(4)))
            // `250-` continues; `250 ` or a bare `250` ends.
            if line.dropFirst(3).first != "-" {
                defer { lines = [] }
                return SMTPReply(code: code, lines: lines)
            }
        }
        return nil
    }
}

enum SMTPError: Error, Equatable {
    /// The server rejected the user name or password.
    case authenticationFailed
    /// The server answered with a failure; a permanent one (5xx) won't change by sending again.
    case refused(SMTPReply)
    /// The server doesn't offer STARTTLS, and the password never goes over a plain connection.
    case insecure
    case closed
    case malformed(String)
}
