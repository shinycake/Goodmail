import Foundation
import MailCore

/// Who a message is from and to, as SMTP's MAIL FROM and RCPT TO name them, and the message to send: its Bcc header
/// taken out, since every recipient receives the same bytes.
struct SMTPEnvelope: Equatable, Sendable {
    var from: String
    var recipients: [String]
    var message: Data

    /// `nil` for a message with no sender or no one to send it to.
    init?(_ raw: Data) {
        let headers = MIMEPart(parsing: raw)
        guard let from = headers.header("From").flatMap({ Contact.list(parsing: $0).first?.address }) else {
            return nil
        }
        var recipients: [String] = []
        for name in ["To", "Cc", "Bcc"] {
            for contact in headers.header(name).map(Contact.list(parsing:)) ?? []
            where !recipients.contains(contact.address) {
                recipients.append(contact.address)
            }
        }
        guard !recipients.isEmpty else { return nil }
        self.from = from
        self.recipients = recipients
        message = Self.removingHeader("Bcc", from: raw)
    }

    /// `raw` without the header `name` and its folded lines. The body is left as it is.
    static func removingHeader(_ name: String, from raw: Data) -> Data {
        var kept = Data()
        var dropping = false
        var lineStart = raw.startIndex
        while lineStart < raw.endIndex {
            let lineEnd = raw[lineStart...].firstIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? raw.endIndex
            let line = raw[lineStart..<lineEnd]
            if line.first == UInt8(ascii: "\r") || line.first == UInt8(ascii: "\n") {
                // The empty line ends the headers.
                kept.append(raw[lineStart...])
                return kept
            }
            let folded = line.first == UInt8(ascii: " ") || line.first == UInt8(ascii: "\t")
            if !folded {
                let field = String(decoding: line.prefix { $0 != UInt8(ascii: ":") }, as: UTF8.self)
                dropping = field.caseInsensitiveCompare(name) == .orderedSame
            }
            if !dropping { kept.append(line) }
            lineStart = lineEnd
        }
        return kept
    }

    /// The message as DATA carries it (RFC 5321 §4.5.2): CRLF line ends, a line starting with a dot gets another,
    /// and the last line ends, so the closing `.` is on its own line.
    static func dotStuffed(_ message: Data) -> Data {
        var data = Data()
        var atLineStart = true
        var previous: UInt8?
        for byte in message {
            if atLineStart, byte == UInt8(ascii: ".") { data.append(UInt8(ascii: ".")) }
            if byte == UInt8(ascii: "\n"), previous != UInt8(ascii: "\r") { data.append(UInt8(ascii: "\r")) }
            data.append(byte)
            atLineStart = byte == UInt8(ascii: "\n")
            previous = byte
        }
        if !atLineStart { data.append(contentsOf: [UInt8(ascii: "\r"), UInt8(ascii: "\n")]) }
        return data
    }
}
