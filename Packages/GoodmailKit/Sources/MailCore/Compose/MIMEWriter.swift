import Foundation

/// Writes a draft as an RFC 5322 message: UTF-8 throughout, `multipart/alternative` with plain text and HTML,
/// and the threading headers replies need.
public enum MIMEWriter {
    public static func message(
        for draft: Draft, from: Contact, date: Date, messageID: String,
        boundary: String = "goodmail-\(UUID().uuidString)"
    ) -> Data {
        var headers: [(String, String)] = [
            ("From", mailbox(from)),
            ("Date", rfc5322Date(date)),
            ("Message-ID", "<\(messageID)>"),
        ]
        if !draft.to.isEmpty { headers.append(("To", draft.to.map(mailbox).joined(separator: ", "))) }
        if !draft.cc.isEmpty { headers.append(("Cc", draft.cc.map(mailbox).joined(separator: ", "))) }
        // The provider delivers to Bcc and removes the header from what others receive.
        if !draft.bcc.isEmpty { headers.append(("Bcc", draft.bcc.map(mailbox).joined(separator: ", "))) }
        headers.append(("Subject", encodedWords(draft.subject)))
        if let inReplyTo = draft.inReplyTo { headers.append(("In-Reply-To", angled(inReplyTo))) }
        if !draft.references.isEmpty {
            headers.append(("References", draft.references.map(angled).joined(separator: " ")))
        }
        headers.append(("MIME-Version", "1.0"))
        headers.append(("Content-Type", "multipart/alternative; boundary=\"\(boundary)\""))

        var lines = headers.map { "\($0.0): \($0.1)" }
        lines.append("")
        for (type, text) in [("text/plain", plainText(draft)), ("text/html", html(draft))] {
            lines += [
                "--\(boundary)",
                "Content-Type: \(type); charset=\"UTF-8\"",
                "Content-Transfer-Encoding: base64",
                "",
                Data(text.utf8).base64EncodedString(options: [
                    .lineLength76Characters, .endLineWithCarriageReturn,
                    .endLineWithLineFeed,
                ]),
            ]
        }
        lines.append("--\(boundary)--")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    static func plainText(_ draft: Draft) -> String {
        let body = draft.body.plain ?? ""
        guard let quote = draft.quote?.plain, !quote.isEmpty else { return body }
        return body + "\n\n" + quote
    }

    static func html(_ draft: Draft) -> String {
        let body = draft.body.html ?? ""
        let quote = draft.quote?.html.map { "<br>\($0)" } ?? ""
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>\(body)\(quote)</body></html>"
    }

    /// `Name <address>`, with the name quoted or MIME-encoded as needed.
    static func mailbox(_ contact: Contact) -> String {
        guard let name = contact.name, !name.isEmpty else { return contact.address }
        let display: String
        if !name.unicodeScalars.allSatisfy(\.isASCII) {
            display = encodedWords(name)
        } else if name.rangeOfCharacter(from: CharacterSet(charactersIn: "()<>[]:;@\\,.\"")) != nil {
            display =
                "\"\(name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        } else {
            display = name
        }
        return "\(display) <\(contact.address)>"
    }

    /// RFC 2047 encoded words for text with non-ASCII characters; ASCII passes through. Each word stays under the
    /// 75-character limit and never splits a character.
    static func encodedWords(_ text: String) -> String {
        guard !text.unicodeScalars.allSatisfy(\.isASCII) else { return text }
        var words: [String] = []
        var chunk = ""
        for character in text {
            if (chunk + String(character)).utf8.count > 45 {
                words.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { words.append(chunk) }
        return words.map { "=?UTF-8?B?\(Data($0.utf8).base64EncodedString())?=" }.joined(separator: "\r\n ")
    }

    private static func angled(_ id: String) -> String {
        id.hasPrefix("<") ? id : "<\(id)>"
    }

    static func rfc5322Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
