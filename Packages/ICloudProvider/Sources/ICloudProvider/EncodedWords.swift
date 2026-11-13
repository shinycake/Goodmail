import Foundation
import MailCore

/// Decodes RFC 2047 encoded words, such as `=?UTF-8?B?16nXnNeV150=?=`, in a header IMAP returns raw.
enum EncodedWords {
    static func decode(_ header: String) -> String {
        var result = ""
        var rest = header[...]
        var lastWasEncoded = false
        while let match = rest.firstMatch(of: /=\?([^?\s]+)\?([BbQq])\?([^?\s]*)\?=/) {
            let gap = rest[..<match.range.lowerBound]
            guard let decoded = decode(charset: match.1, encoding: match.2, text: match.3) else {
                result += rest[..<match.range.upperBound]
                rest = rest[match.range.upperBound...]
                lastWasEncoded = false
                continue
            }
            // Whitespace between two encoded words is only folding (RFC 2047 §6.2).
            if !(lastWasEncoded && gap.allSatisfy(\.isWhitespace)) { result += gap }
            result += decoded
            rest = rest[match.range.upperBound...]
            lastWasEncoded = true
        }
        return result + rest
    }

    private static func decode(charset: Substring, encoding: Substring, text: Substring) -> String? {
        // `charset*language` (RFC 2231 §5).
        let charset = String(charset.prefix { $0 != "*" })
        let bytes: Data?
        switch encoding {
        case "B", "b":
            let padding = String(repeating: "=", count: (4 - text.count % 4) % 4)
            bytes = Data(base64Encoded: text + padding)
        default:
            bytes = quotedPrintable(text)
        }
        return bytes.map { TextDecoding.string(from: $0, declaredCharset: charset) }
    }

    /// The `Q` encoding: `_` is a space, `=XX` a byte.
    private static func quotedPrintable(_ text: Substring) -> Data? {
        let bytes = Array(text.utf8)
        var data = Data()
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "="):
                guard index + 2 < bytes.count,
                    let byte = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16)
                else { return nil }
                data.append(byte)
                index += 3
            case UInt8(ascii: "_"):
                data.append(UInt8(ascii: " "))
                index += 1
            case let byte:
                data.append(byte)
                index += 1
            }
        }
        return data
    }
}

/// IMAP's mailbox-name encoding (RFC 3501 §5.1.3): UTF-16 in base64 between `&` and `-`, with `,` for `/`.
enum ModifiedUTF7 {
    static func decode(_ name: String) -> String {
        var result = ""
        var rest = name[...]
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let encoded = rest[rest.index(after: ampersand)...].prefix { $0 != "-" }
            let afterDash =
                rest.index(ampersand, offsetBy: encoded.count + 2, limitedBy: rest.endIndex) ?? rest.endIndex
            rest = rest[afterDash...]
            guard !encoded.isEmpty else {
                result += "&"
                continue
            }
            let base64 = String(encoded).replacing(",", with: "/")
            let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let bytes = Data(base64Encoded: padded), let text = String(data: bytes, encoding: .utf16BigEndian)
            else {
                result += "&\(encoded)-"
                continue
            }
            result += text
        }
        return result + rest
    }
}
