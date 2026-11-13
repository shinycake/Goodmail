import Foundation

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
