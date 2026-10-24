import Foundation

/// A message being written: who it goes to, what it says, and the conversation it answers.
public struct Draft: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var accountID: AccountID
    public var to: [Contact]
    public var cc: [Contact]
    public var bcc: [Contact]
    public var subject: String
    /// What the writer typed, as HTML and as plain text.
    public var body: MessageBody
    /// The quoted conversation sent below the body, as HTML and as plain text. Kept apart so the editor shows only
    /// what is being written.
    public var quote: MessageBody?
    /// The provider's thread this message joins, for replies and forwards.
    public var threadID: String?
    /// `In-Reply-To` and `References`, so every mail client threads the reply.
    public var inReplyTo: String?
    public var references: [String]

    public init(
        id: UUID = UUID(),
        accountID: AccountID,
        to: [Contact] = [],
        cc: [Contact] = [],
        bcc: [Contact] = [],
        subject: String = "",
        body: MessageBody = MessageBody(html: "", plain: ""),
        quote: MessageBody? = nil,
        threadID: String? = nil,
        inReplyTo: String? = nil,
        references: [String] = []
    ) {
        self.id = id
        self.accountID = accountID
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.quote = quote
        self.threadID = threadID
        self.inReplyTo = inReplyTo
        self.references = references
    }

    public var recipients: [Contact] { to + cc + bcc }

    /// A reply to `message`, from the account at `accountEmail`. Reply all adds everyone else on it, except the
    /// account itself.
    public static func reply(
        to message: Message, all: Bool, accountEmail: String, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> Draft {
        let isMine = { (contact: Contact) in contact.address.caseInsensitiveCompare(accountEmail) == .orderedSame }
        // Replying to your own message goes back to the people you wrote to.
        let primary = isMine(message.from) ? message.to : (message.replyTo.isEmpty ? [message.from] : message.replyTo)
        var to = unique(primary)
        var cc: [Contact] = []
        if all {
            cc = unique((message.to + message.cc).filter { !isMine($0) && !contains(to, $0) })
            if !isMine(message.from) { to = to.filter { !isMine($0) } }
        }
        return Draft(
            accountID: message.id.accountID,
            to: to,
            cc: cc,
            subject: prefixed(message.subject, with: "Re:", recognizing: ["re:"]),
            quote: quote(of: message, locale: locale, timeZone: timeZone),
            threadID: message.threadID,
            inReplyTo: message.internetMessageID,
            references: message.references + (message.internetMessageID.map { [$0] } ?? [])
        )
    }

    /// A forward of `message` to people yet to be chosen, in the same thread.
    public static func forward(_ message: Message, locale: Locale = .current, timeZone: TimeZone = .current) -> Draft {
        Draft(
            accountID: message.id.accountID,
            subject: prefixed(message.subject, with: "Fwd:", recognizing: ["fwd:", "fw:"]),
            quote: forwardedQuote(of: message, locale: locale, timeZone: timeZone),
            threadID: message.threadID,
            references: message.references + (message.internetMessageID.map { [$0] } ?? [])
        )
    }

    private static func prefixed(_ subject: String, with prefix: String, recognizing known: [String]) -> String {
        let lower = subject.lowercased()
        return known.contains(where: lower.hasPrefix) ? subject : "\(prefix) \(subject)"
    }

    private static func contains(_ list: [Contact], _ contact: Contact) -> Bool {
        list.contains { $0.address.caseInsensitiveCompare(contact.address) == .orderedSame }
    }

    private static func unique(_ contacts: [Contact]) -> [Contact] {
        contacts.reduce(into: []) { result, contact in
            if !contains(result, contact) { result.append(contact) }
        }
    }

    private static func dateText(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "On Oct 12, 2026 at 9:10 AM, Dana Levi <dana@example.com> wrote:" above the original, as Gmail quotes.
    static func quote(of message: Message, locale: Locale, timeZone: TimeZone) -> MessageBody {
        let attribution =
            "On \(dateText(message.date, locale: locale, timeZone: timeZone)), "
            + "\(mailbox(message.from)) wrote:"
        let original = originalHTML(message)
        let html = """
            <div class="gmail_quote"><div dir="ltr" class="gmail_attr">\(HTMLText.escape(attribution))<br></div>\
            <blockquote class="gmail_quote" type="cite" style="margin:0 0 0 .8ex;border-left:1px solid #ccc;\
            padding-left:1ex">\(original)</blockquote></div>
            """
        let plain =
            attribution + "\n"
            + (message.body.plain ?? "").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
        return MessageBody(html: html, plain: plain)
    }

    static func forwardedQuote(of message: Message, locale: Locale, timeZone: TimeZone) -> MessageBody {
        var lines = [
            "---------- Forwarded message ---------",
            "From: \(mailbox(message.from))",
            "Date: \(dateText(message.date, locale: locale, timeZone: timeZone))",
            "Subject: \(message.subject)",
        ]
        if !message.to.isEmpty { lines.append("To: \(message.to.map(mailbox).joined(separator: ", "))") }
        if !message.cc.isEmpty { lines.append("Cc: \(message.cc.map(mailbox).joined(separator: ", "))") }
        let header = lines.map(HTMLText.escape).joined(separator: "<br>")
        let html = """
            <div class="gmail_quote"><div dir="ltr" class="gmail_attr">\(header)<br></div><br>\
            \(originalHTML(message))</div>
            """
        return MessageBody(html: html, plain: lines.joined(separator: "\n") + "\n\n" + (message.body.plain ?? ""))
    }

    private static func mailbox(_ contact: Contact) -> String {
        guard let name = contact.name, !name.isEmpty else { return contact.address }
        return "\(name) <\(contact.address)>"
    }

    /// The original's HTML body, or its plain text as HTML, one block per line.
    private static func originalHTML(_ message: Message) -> String {
        if let html = message.body.html, !html.isEmpty { return HTMLText.bodyContent(of: html) }
        return (message.body.plain ?? "").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "<br>" : "<div dir=\"auto\">\(HTMLText.escape(String($0)))</div>" }.joined()
    }
}

/// Small HTML helpers for building outgoing mail.
public enum HTMLText {
    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// What's inside `<body>`, so a quoted document nests in ours. A fragment comes back as it is.
    static func bodyContent(of html: String) -> String {
        guard let open = html.range(of: #"<body[^>]*>"#, options: [.regularExpression, .caseInsensitive]) else {
            return html
        }
        let rest = html[open.upperBound...]
        let close = rest.range(of: "</body>", options: [.caseInsensitive, .backwards])
        return String(rest[..<(close?.lowerBound ?? rest.endIndex)])
    }
}
