import Foundation

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
        if let text = String(data: data, encoding: .utf8) { return text }
        if let charset = declaredCharset.map(normalized), let encoding = encoding(named: charset),
            let text = String(data: data, encoding: encoding)
        {
            return text
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
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
