public import Foundation

extension Draft {
    /// A new message from a `mailto:` link (RFC 6068), sent from `account`: its addresses, and its `to`, `cc`,
    /// `bcc`, `subject` and `body` fields. `nil` when the URL isn't a `mailto:` link.
    public init?(mailto url: URL, from account: AccountID) {
        guard url.scheme?.lowercased() == "mailto",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        var fields: [String: [String]] = [:]
        for item in components.percentEncodedQueryItems ?? [] {
            let value = item.value.flatMap { $0.removingPercentEncoding } ?? ""
            fields[item.name.lowercased(), default: []].append(value)
        }
        let path = components.percentEncodedPath.removingPercentEncoding ?? ""
        func addresses(_ lists: [String]) -> [Contact] {
            lists.flatMap { Contact.list(parsing: $0) }
        }
        let body = fields["body"]?.first ?? ""
        self.init(
            accountID: account,
            to: addresses([path] + (fields["to"] ?? [])),
            cc: addresses(fields["cc"] ?? []),
            bcc: addresses(fields["bcc"] ?? []),
            subject: fields["subject"]?.first ?? "",
            body: MessageBody(html: Self.html(fromPlain: body), plain: body))
    }

    /// Plain text as HTML, one block per line, as the composer writes it.
    static func html(fromPlain text: String) -> String {
        guard !text.isEmpty else { return "" }
        return text.textLines
            .map { $0.isEmpty ? "<br>" : "<div dir=\"auto\">\(HTMLText.escape(String($0)))</div>" }.joined()
    }
}
