public import Foundation

/// How a mailing list lets a reader leave it, from the message's `List-Unsubscribe` header (RFC 2369) and its
/// one-click marker `List-Unsubscribe-Post` (RFC 8058). One way is kept, the one that asks least of the reader:
/// a one-click request, else a message to the list, else a page to finish on.
public enum Unsubscribe: Hashable, Codable, Sendable {
    /// An HTTPS `POST` of `List-Unsubscribe=One-Click` does it, with nothing to open or send.
    case oneClick(URL)
    /// A message to the list's address does it, sent for the reader from their account.
    case mail(Mailto)
    /// A web page finishes it, so the reader opens it.
    case page(URL)

    /// A `mailto:` URI's parts that an unsubscribe message needs.
    public struct Mailto: Hashable, Codable, Sendable {
        public var to: [String]
        public var subject: String
        public var body: String

        public init(to: [String], subject: String = "", body: String = "") {
            self.to = to
            self.subject = subject
            self.body = body
        }

        /// `nil` for a URI that isn't `mailto:` or names nobody.
        public init?(_ url: URL) {
            guard url.scheme?.lowercased() == "mailto",
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return nil }
            let query = components.queryItems ?? []
            func value(_ name: String) -> String? {
                query.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
            }
            // The URI comes from the list's sender, and percent-decoding can hide anything in it, so only plain
            // addresses go on: a CR or LF in one would start a header of the sender's choosing in our message.
            let addresses = (components.path.split(separator: ",") + (value("to")?.split(separator: ",") ?? []))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter(Self.isPlainAddress)
            guard !addresses.isEmpty else { return nil }
            self.init(to: addresses, subject: MIMEWriter.oneLine(value("subject") ?? ""), body: value("body") ?? "")
        }

        /// `local@domain`, with no whitespace, control characters or the punctuation that ends or adds an address.
        static func isPlainAddress(_ address: String) -> Bool {
            address.wholeMatch(of: /[^\s<>,;:"()\[\]\\@]+@[^\s<>,;:"()\[\]\\@]+/) != nil
                && !address.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }
    }

    /// `nil` when the headers offer no way this app can take: no header, or only URIs it can't use.
    public init?(listUnsubscribe header: String, post: String?) {
        let uris = Self.uris(in: header)
        let secure = uris.filter { $0.scheme?.lowercased() == "https" }
        let oneClick = post.map(Self.isOneClick) ?? false
        if oneClick, let url = secure.first {
            self = .oneClick(url)
        } else if let mailto = uris.lazy.compactMap(Mailto.init).first {
            self = .mail(mailto)
        } else if let url = secure.first ?? uris.first(where: { $0.scheme?.lowercased() == "http" }) {
            self = .page(url)
        } else {
            return nil
        }
    }

    /// Every `<...>` in the header, in order. Whitespace inside the brackets is folding, not part of the URI.
    static func uris(in header: String) -> [URL] {
        header.matches(of: /<([^<>]*)>/).compactMap { match in
            URL(string: match.output.1.filter { !$0.isWhitespace })
        }
    }

    /// RFC 8058 asks for exactly the `List-Unsubscribe=One-Click` pair.
    private static func isOneClick(_ post: String) -> Bool {
        post.split(separator: ";").contains {
            $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("List-Unsubscribe=One-Click")
                == .orderedSame
        }
    }
}
