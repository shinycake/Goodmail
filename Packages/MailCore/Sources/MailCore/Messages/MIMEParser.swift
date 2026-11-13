import Foundation

extension MIMEPart {
    /// Parses a raw RFC 5322 message, as IMAP's `BODY[]` or Graph's `$value` return it: headers unfolded and their
    /// encoded words decoded, multiparts split, and each leaf's transfer encoding undone. Part IDs follow IMAP's
    /// section numbers (RFC 3501 §6.4.5), so a part can be fetched again on its own: a multipart's children are `1`,
    /// `2`, and theirs `1.1`; a message that isn't multipart is part `1`.
    public init(parsing raw: Data) {
        let entity = MIMEEntity(Array(raw))
        self.init(entity, partID: entity.contentType.isMultipart ? "" : "1")
    }

    private init(_ entity: MIMEEntity, partID: String) {
        let contentType = entity.contentType
        let children: [MIMEPart]
        let data: Data?
        if contentType.isMultipart, let boundary = contentType.parameters["boundary"] {
            children = MIMEEntity.parts(of: entity.body, boundary: boundary).enumerated().map { index, child in
                MIMEPart(child, partID: partID.isEmpty ? "\(index + 1)" : "\(partID).\(index + 1)")
            }
            data = nil
        } else {
            children = []
            data = entity.decodedBody
        }
        self.init(
            partID: partID,
            mimeType: contentType.mimeType,
            headers: entity.headers,
            filename: entity.filename ?? "",
            data: data,
            size: data?.count ?? 0,
            parts: children
        )
    }
}

/// One entity's headers and raw body (RFC 2045).
private struct MIMEEntity {
    var headers: [(name: String, value: String)]
    var body: ArraySlice<UInt8>

    init(_ bytes: some Collection<UInt8>) {
        let bytes = Array(bytes)
        let (headerEnd, bodyStart) = Self.headerEnd(in: bytes)
        headers = Self.headers(in: bytes[..<headerEnd])
        body = bytes[bodyStart...]
    }

    func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// `text/plain` when the header is missing (RFC 2045 §5.2).
    var contentType: HeaderValue { HeaderValue(header("Content-Type") ?? "text/plain") }

    var filename: String? {
        header("Content-Disposition").flatMap { HeaderValue($0).parameters["filename"] }
            ?? contentType.parameters["name"]
    }

    var decodedBody: Data {
        switch header("Content-Transfer-Encoding")?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "base64":
            let text = String(decoding: body.filter { !Self.whitespace.contains($0) }, as: UTF8.self)
            let padded = text + String(repeating: "=", count: (4 - text.count % 4) % 4)
            return Data(base64Encoded: padded, options: .ignoreUnknownCharacters) ?? Data(body)
        case "quoted-printable":
            return Self.quotedPrintable(body)
        default:
            return Data(Self.trimmingFinalLineBreak(body))
        }
    }

    private static let whitespace: Set<UInt8> = [0x20, 0x09, 0x0D, 0x0A]

    /// Where the headers end and the body starts: after the first empty line, CRLF or bare LF.
    private static func headerEnd(in bytes: [UInt8]) -> (headerEnd: Int, bodyStart: Int) {
        if bytes.first == 0x0A { return (0, 1) }
        if bytes.starts(with: [0x0D, 0x0A]) { return (0, 2) }
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 0x0A {
                if bytes[index + 1] == 0x0A { return (index + 1, index + 2) }
                if bytes[index + 1] == 0x0D, index + 2 < bytes.count, bytes[index + 2] == 0x0A {
                    return (index + 1, index + 3)
                }
            }
            index += 1
        }
        return (bytes.count, bytes.count)
    }

    /// Unfolds continuation lines and decodes encoded words. Header bytes that aren't UTF-8 are read as Latin-1.
    private static func headers(in bytes: ArraySlice<UInt8>) -> [(name: String, value: String)] {
        let text = TextDecoding.string(from: Data(bytes), declaredCharset: nil)
        var headers: [(name: String, value: String)] = []
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            if line.first == " " || line.first == "\t", let last = headers.popLast() {
                headers.append((last.name, last.value + " " + line.trimmingCharacters(in: .whitespaces)))
            } else if let colon = line.firstIndex(of: ":") {
                headers.append(
                    (
                        String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                        String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    ))
            }
        }
        return headers.map { ($0.name, EncodedWords.decode($0.value)) }
    }

    /// The entities between `--boundary` lines, up to `--boundary--`. Preamble and epilogue are dropped.
    static func parts(of body: ArraySlice<UInt8>, boundary: String) -> [MIMEEntity] {
        let delimiter = Array("--\(boundary)".utf8)
        var parts: [MIMEEntity] = []
        var partStart: Int?
        var lineStart = body.startIndex
        while lineStart < body.endIndex {
            let lineEnd = body[lineStart...].firstIndex(of: 0x0A) ?? body.endIndex
            let line = body[lineStart..<lineEnd]
            if line.starts(with: delimiter) {
                let rest = line.dropFirst(delimiter.count)
                if let start = partStart {
                    // The line break before a delimiter belongs to the delimiter (RFC 2046 §5.1.1).
                    parts.append(MIMEEntity(trimmingFinalLineBreak(body[start..<lineStart])))
                }
                if rest.starts(with: [0x2D, 0x2D]) { return parts }
                partStart = min(lineEnd + 1, body.endIndex)
            }
            lineStart = min(lineEnd + 1, body.endIndex)
        }
        // A message cut off before its closing delimiter keeps the part it was in.
        if let start = partStart, start < body.endIndex { parts.append(MIMEEntity(body[start...])) }
        return parts
    }

    private static func trimmingFinalLineBreak(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var bytes = bytes
        if bytes.last == 0x0A { bytes.removeLast() }
        if bytes.last == 0x0D { bytes.removeLast() }
        return bytes
    }

    /// RFC 2045 §6.7: `=XX` is a byte, `=` at the end of a line joins it to the next.
    private static func quotedPrintable(_ bytes: ArraySlice<UInt8>) -> Data {
        var data = Data()
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "=") else {
                data.append(byte)
                index += 1
                continue
            }
            let next = bytes[(index + 1)...].prefix(2)
            if next.first == 0x0A {
                index += 2
            } else if next.elementsEqual([0x0D, 0x0A]) {
                index += 3
            } else if next.count == 2, let value = UInt8(String(decoding: next, as: UTF8.self), radix: 16) {
                data.append(value)
                index += 3
            } else {
                data.append(byte)
                index += 1
            }
        }
        return data
    }
}

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
