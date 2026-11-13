import Foundation

/// A structured header such as `text/plain; charset="utf-8"`: its value and its parameters, with RFC 2231's
/// continued and charset-encoded parameters (`name*0*=utf-8''%D7%A9`) put back together.
struct HeaderValue {
    var value: String
    /// Keys are lower-cased.
    var parameters: [String: String]

    var mimeType: String { value.lowercased() }
    var isMultipart: Bool { mimeType.hasPrefix("multipart/") }

    init(_ header: String) {
        var fields = Self.fields(header)
        value = fields.isEmpty ? "" : fields.removeFirst().trimmingCharacters(in: .whitespaces)
        var plain: [String: String] = [:]
        var sections: [String: [(index: Int, value: String, encoded: Bool)]] = [:]
        for field in fields {
            guard let equals = field.firstIndex(of: "=") else { continue }
            var name = field[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let raw = field[field.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let unquoted = raw.hasPrefix("\"") ? Self.unquoted(raw) : raw
            let encoded = name.hasSuffix("*")
            if encoded { name.removeLast() }
            let pieces = name.split(separator: "*", maxSplits: 1)
            if pieces.count == 2, let index = Int(pieces[1]) {
                sections[String(pieces[0]), default: []].append((index, unquoted, encoded))
            } else if encoded {
                sections[name, default: []].append((0, unquoted, true))
            } else {
                plain[name] = unquoted
            }
        }
        for (name, pieces) in sections {
            plain[name] = Self.joined(pieces.sorted { $0.index < $1.index })
        }
        parameters = plain
    }

    /// Splits on semicolons outside quotes.
    private static func fields(_ header: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for character in header {
            if escaped {
                escaped = false
            } else if character == "\\" && inQuotes {
                escaped = true
            } else if character == "\"" {
                inQuotes.toggle()
            } else if character == ";" && !inQuotes {
                fields.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        fields.append(current)
        return fields
    }

    private static func unquoted(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text.dropFirst() {
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// RFC 2231 §4: the first encoded section names the charset (`utf-8'lang'`); encoded sections are %-escaped.
    private static func joined(_ pieces: [(index: Int, value: String, encoded: Bool)]) -> String {
        var charset: String?
        var bytes = Data()
        for (position, piece) in pieces.enumerated() {
            guard piece.encoded else {
                bytes.append(contentsOf: piece.value.utf8)
                continue
            }
            var value = piece.value[...]
            if position == 0 {
                let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3 {
                    charset = parts[0].isEmpty ? nil : String(parts[0])
                    value = parts[2]
                }
            }
            bytes.append(Data(percentDecoding: value))
        }
        return TextDecoding.string(from: bytes, declaredCharset: charset)
    }
}

extension Data {
    fileprivate init(percentDecoding text: Substring) {
        var bytes: [UInt8] = []
        var index = text.utf8.startIndex
        let utf8 = text.utf8
        while index < utf8.endIndex {
            let byte = utf8[index]
            if byte == UInt8(ascii: "%"),
                let end = utf8.index(index, offsetBy: 3, limitedBy: utf8.endIndex),
                let value = UInt8(String(decoding: utf8[utf8.index(after: index)..<end], as: UTF8.self), radix: 16)
            {
                bytes.append(value)
                index = end
            } else {
                bytes.append(byte)
                index = utf8.index(after: index)
            }
        }
        self.init(bytes)
    }
}
