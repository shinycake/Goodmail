public import Foundation

/// A MIME part as a provider delivers it, with its transfer encoding already undone. Providers build this tree;
/// `MailCore` decides what is body and what is attachment, the same way for every provider.
public struct MIMEPart: Sendable {
    public var partID: String
    public var mimeType: String
    /// Header names are as sent; look them up with `header(_:)`.
    public var headers: [(name: String, value: String)]
    public var filename: String
    /// The decoded content, or `nil` when the provider left it to fetch on demand.
    public var data: Data?
    public var size: Int
    public var fetchToken: String?
    public var parts: [MIMEPart]

    public init(
        partID: String,
        mimeType: String,
        headers: [(name: String, value: String)] = [],
        filename: String = "",
        data: Data? = nil,
        size: Int = 0,
        fetchToken: String? = nil,
        parts: [MIMEPart] = []
    ) {
        self.partID = partID
        self.mimeType = mimeType.lowercased()
        self.headers = headers
        self.filename = filename
        self.data = data
        self.size = size
        self.fetchToken = fetchToken
        self.parts = parts
    }

    /// A message with nothing in it: no headers, no body and no attachments, for a provider that returns a message
    /// without its content.
    public static let empty = MIMEPart(partID: "", mimeType: "multipart/mixed")

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// This part or the one below it with `partID`, as an attachment names its part.
    public func part(withID partID: String) -> MIMEPart? {
        self.partID == partID ? self : parts.lazy.compactMap { $0.part(withID: partID) }.first
    }

    /// The `charset` parameter of the Content-Type header.
    var charset: String? {
        header("Content-Type").flatMap { HeaderValue($0).parameters["charset"] }
    }

    var isAttachmentDisposition: Bool {
        header("Content-Disposition")?.lowercased().hasPrefix("attachment") == true
    }

    var contentID: String? {
        header("Content-ID")?.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    /// The body to read and the files the message carries.
    public func content() -> (body: MessageBody, attachments: [Attachment]) {
        var body = MessageBody()
        var attachments: [Attachment] = []
        collect(into: &body, attachments: &attachments, inAlternative: false)
        return (body, attachments)
    }

    private func collect(into body: inout MessageBody, attachments: inout [Attachment], inAlternative: Bool) {
        if mimeType.hasPrefix("multipart/") {
            // In an alternative, every part says the same thing; the richest one we read wins.
            for part in parts {
                part.collect(into: &body, attachments: &attachments, inAlternative: mimeType == "multipart/alternative")
            }
            return
        }
        let isText = mimeType == "text/plain" || mimeType == "text/html"
        if isText, !isAttachmentDisposition, let data, filename.isEmpty {
            let text = TextDecoding.string(from: data, declaredCharset: charset)
            if mimeType == "text/html" {
                body.html = append(text, to: body.html, separatedBy: "<br>", replacing: inAlternative)
            } else {
                body.plain = append(text, to: body.plain, separatedBy: "\n\n", replacing: inAlternative)
            }
            return
        }
        attachments.append(
            Attachment(
                id: partID,
                filename: filename.isEmpty ? (contentID ?? partID) : filename,
                mimeType: mimeType,
                size: data?.count ?? size,
                contentID: contentID,
                isInline: contentID != nil && !isAttachmentDisposition,
                fetchToken: fetchToken
            )
        )
    }

    /// Mixed messages can carry several text parts (a body, then a forwarded one); keep them all, in order.
    private func append(_ text: String, to existing: String?, separatedBy separator: String, replacing: Bool) -> String
    {
        guard let existing, !replacing else { return text }
        return existing + separator + text
    }
}

/// Text from bytes whose label may lie.
public enum TextDecoding {
    /// Gmail hands back bodies already converted to UTF-8 while their Content-Type still names the original charset
    /// (recorded: `windows-1255`, `iso-8859-8-i`), so valid UTF-8 wins. Bytes that aren't valid UTF-8 use the
    /// declared charset, which IMAP will need, and Latin-1 last, which never fails.
    public static func string(from data: Data, declaredCharset: String?) -> String {
        if let text = String(data: data, encoding: .utf8) ?? utf8CutShort(data, declaredCharset: declaredCharset) {
            return text
        }
        if let charset = declaredCharset.map(normalized), let encoding = encoding(named: charset),
            let text = String(data: data, encoding: encoding)
        {
            return text
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// UTF-8 that ends partway through a character, as the start of a message that IMAP fetches for a snippet can,
    /// without that last character. Read as Latin-1 instead, every character past the first in a mail's invisible
    /// preheader filler (U+034F, U+200C, no-break spaces) turns into "Í Â â". It counts as UTF-8 only when it says it
    /// is, or when it has a whole character of more than one byte too, so a Latin-1 "café" keeps its "é". Undeclared
    /// ASCII cut inside its first other character still reads as Latin-1; IMAP's snippet fetch carries the charset.
    private static func utf8CutShort(_ data: Data, declaredCharset: String?) -> String? {
        let bytes = [UInt8](data.suffix(4))
        // The last byte that starts a character, and how many bytes that character takes.
        guard let start = bytes.lastIndex(where: { $0 & 0b1100_0000 != 0b1000_0000 }) else { return nil }
        let length =
            switch bytes[start] {
            case 0b1100_0000...0b1101_1111: 2
            case 0b1110_0000...0b1110_1111: 3
            case 0b1111_0000...0b1111_0111: 4
            default: 1
            }
        guard bytes.count - start < length else { return nil }
        let whole = data.prefix(data.count - (bytes.count - start))
        let saysUTF8 = declaredCharset.map(normalized).map { $0 == "utf-8" || $0 == "utf8" } ?? false
        guard saysUTF8 || whole.contains(where: { $0 >= 0b1100_0000 }),
            let text = String(data: whole, encoding: .utf8)
        else { return nil }
        return text
    }

    /// `iso-8859-8-i` (logical order) and `iso-8859-8-e` share their bytes with `iso-8859-8`.
    private static func normalized(_ name: String) -> String {
        let lower = name.lowercased()
        return lower.hasPrefix("iso-8859-8") ? "iso-8859-8" : lower
    }

    private static func encoding(named name: String) -> String.Encoding? {
        #if canImport(Darwin)
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cf != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        #else
            // Linux test builds: swift-corelibs-foundation knows only the charsets `String.Encoding` names, so no
            // windows-1255.
            return String.Encoding(ianaName: name)
        #endif
    }
}
