public import Foundation

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
    /// Files sent with the message, in the order they were added.
    public var attachments: [DraftAttachment]
    /// The provider's saved copy of this draft, replaced when it is saved again and removed once it is sent.
    public var savedDraft: Message.ID?
    /// One of the account's other addresses to send as, such as a Gmail send-as alias. `nil` sends from the
    /// account's own address.
    public var alias: Contact?

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
        references: [String] = [],
        attachments: [DraftAttachment] = [],
        savedDraft: Message.ID? = nil,
        alias: Contact? = nil
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
        self.attachments = attachments
        self.savedDraft = savedDraft
        self.alias = alias
    }

    private enum CodingKeys: String, CodingKey {
        case id, accountID, to, cc, bcc, subject, body, quote, threadID, inReplyTo, references, attachments,
            savedDraft, alias
    }

    /// Drafts saved before attachments existed decode with none, and those saved before aliases with no alias.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            accountID: try container.decode(AccountID.self, forKey: .accountID),
            to: try container.decode([Contact].self, forKey: .to),
            cc: try container.decode([Contact].self, forKey: .cc),
            bcc: try container.decode([Contact].self, forKey: .bcc),
            subject: try container.decode(String.self, forKey: .subject),
            body: try container.decode(MessageBody.self, forKey: .body),
            quote: try container.decodeIfPresent(MessageBody.self, forKey: .quote),
            threadID: try container.decodeIfPresent(String.self, forKey: .threadID),
            inReplyTo: try container.decodeIfPresent(String.self, forKey: .inReplyTo),
            references: try container.decode([String].self, forKey: .references),
            attachments: try container.decodeIfPresent([DraftAttachment].self, forKey: .attachments) ?? [],
            savedDraft: try container.decodeIfPresent(Message.ID.self, forKey: .savedDraft),
            alias: try container.decodeIfPresent(Contact.self, forKey: .alias)
        )
    }

    public var recipients: [Contact] { to + cc + bcc }

    /// Who the message goes out as: the account, or its alias under the account's name when the alias has none.
    public func sender(account: Contact) -> Contact {
        guard let alias else { return account }
        return alias.name?.isEmpty == false ? alias : Contact(name: account.name, address: alias.address)
    }

    /// The alias a message about `message` goes from, as Gmail picks it: the one the account sent it from, else the
    /// first it was sent to. `nil` when it involves none, so the account's own address answers.
    static func alias(for message: Message, among aliases: [Contact]) -> Contact? {
        ([message.from] + message.to + message.cc).lazy.compactMap { alias(matching: $0, among: aliases) }.first
    }

    private static func alias(matching contact: Contact, among aliases: [Contact]) -> Contact? {
        aliases.first { $0.address.caseInsensitiveCompare(contact.address) == .orderedSame }
    }

    /// A reply to `message`, from the account at `accountEmail`, or from the one of its `aliases` the message was
    /// sent to. Reply all adds everyone else on it, except the account and its aliases.
    public static func reply(
        to message: Message, all: Bool, accountEmail: String, aliases: [Contact] = [],
        wording: QuoteWording = .english, timeZone: TimeZone = .current
    ) -> Draft {
        let mine = [Contact(name: nil, address: accountEmail)] + aliases
        let isMine = { (contact: Contact) in contains(mine, contact) }
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
            quote: quote(of: message, wording: wording, timeZone: timeZone),
            threadID: message.threadID,
            inReplyTo: message.internetMessageID,
            references: message.references + (message.internetMessageID.map { [$0] } ?? []),
            alias: alias(for: message, among: aliases)
        )
    }

    /// A forward of `message` to people yet to be chosen, in the same thread, with the files it carries, from the
    /// one of the account's `aliases` it was sent to, if any.
    public static func forward(
        _ message: Message, aliases: [Contact] = [], wording: QuoteWording = .english, timeZone: TimeZone = .current
    ) -> Draft {
        Draft(
            accountID: message.id.accountID,
            subject: prefixed(message.subject, with: "Fwd:", recognizing: ["fwd:", "fw:"]),
            quote: forwardedQuote(of: message, wording: wording, timeZone: timeZone),
            threadID: message.threadID,
            references: message.references + (message.internetMessageID.map { [$0] } ?? []),
            attachments: forwardedFiles(of: message),
            alias: alias(for: message, among: aliases)
        )
    }

    /// A forward of `message` to people yet to be chosen, carrying the whole original as a `message/rfc822` file
    /// rather than quoting it, so its headers, body and files reach the recipient exactly as they came.
    /// It goes from the one of the account's `aliases` the original was sent to, if any.
    public static func forwardAsAttachment(
        _ message: Message, aliases: [Contact] = [], wording: QuoteWording = .english
    ) -> Draft {
        Draft(
            accountID: message.id.accountID,
            subject: prefixed(message.subject, with: "Fwd:", recognizing: ["fwd:", "fw:"]),
            threadID: message.threadID,
            references: message.references + (message.internetMessageID.map { [$0] } ?? []),
            attachments: [
                DraftAttachment(
                    filename: emlName(message.subject, untitled: wording.untitledMessage), mimeType: "message/rfc822",
                    content: .message(message.id, size: estimatedSize(of: message)))
            ],
            alias: alias(for: message, among: aliases)
        )
    }

    /// A new message written from a copy of `message`: its recipients, subject, body and files, outside its thread,
    /// so a message already sent can go again, changed or to someone else, from the alias it went from.
    public static func editAsNew(_ message: Message, aliases: [Contact] = []) -> Draft {
        Draft(
            accountID: message.id.accountID,
            to: message.to,
            cc: message.cc,
            bcc: message.bcc,
            subject: message.subject,
            body: message.body,
            attachments: forwardedFiles(of: message),
            alias: alias(matching: message.from, among: aliases)
        )
    }

    /// A draft saved with the provider, reopened to edit and send, from the alias it was saved from. Its files stay
    /// with the provider until it goes.
    public static func editing(_ message: Message, aliases: [Contact] = []) -> Draft {
        Draft(
            accountID: message.id.accountID,
            to: message.to,
            cc: message.cc,
            bcc: message.bcc,
            subject: message.subject,
            body: message.body,
            threadID: message.threadID,
            inReplyTo: message.references.last,
            references: message.references,
            attachments: forwardedFiles(of: message),
            savedDraft: message.id,
            alias: alias(matching: message.from, among: aliases)
        )
    }

    /// The files a reader lists for `message`, to send on without downloading them first.
    private static func forwardedFiles(of message: Message) -> [DraftAttachment] {
        message.attachments.filter { !$0.isInline || $0.contentID == nil }.map {
            DraftAttachment(filename: $0.filename, mimeType: $0.mimeType, content: .forwarded($0, in: message.id))
        }
    }

    /// The subject as a file name, without the characters file systems refuse.
    static func emlName(_ subject: String, untitled: String) -> String {
        let refused = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let name = String(String.UnicodeScalarView(subject.unicodeScalars.filter { !refused.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name.isEmpty ? untitled : String(name.prefix(100))).eml"
    }

    /// About how big the original is, for the composer's size limit, before its bytes are fetched.
    private static func estimatedSize(of message: Message) -> Int {
        (message.body.html?.utf8.count ?? 0) + (message.body.plain?.utf8.count ?? 0)
            + message.attachments.reduce(0) { $0 + $1.size * 4 / 3 }
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
    static func quote(of message: Message, wording: QuoteWording, timeZone: TimeZone) -> MessageBody {
        let attribution = wording.attribution(
            wording.isolated(dateText(message.date, locale: wording.locale, timeZone: timeZone)),
            wording.isolated(mailbox(message.from)))
        let original = originalHTML(message)
        let html = """
            <div class="gmail_quote"><div dir="\(wording.direction)" class="gmail_attr">\(HTMLText.escape(attribution))<br></div>\
            <blockquote class="gmail_quote" type="cite" style="margin:0 0 0 .8ex;border-left:1px solid #ccc;\
            padding-left:1ex">\(original)</blockquote></div>
            """
        let plain =
            attribution + "\n"
            + (message.body.plain ?? "").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: "\n")
        return MessageBody(html: html, plain: plain)
    }

    static func forwardedQuote(of message: Message, wording: QuoteWording, timeZone: TimeZone) -> MessageBody {
        let field = { (name: String, value: String) in "\(name) \(wording.isolated(value))" }
        var lines = [
            wording.forwardedMessage,
            field(wording.from, mailbox(message.from)),
            field(wording.date, dateText(message.date, locale: wording.locale, timeZone: timeZone)),
            field(wording.subject, message.subject),
        ]
        if !message.to.isEmpty { lines.append(field(wording.to, message.to.map(mailbox).joined(separator: ", "))) }
        if !message.cc.isEmpty { lines.append(field(wording.cc, message.cc.map(mailbox).joined(separator: ", "))) }
        let header = lines.map(HTMLText.escape).joined(separator: "<br>")
        let html = """
            <div class="gmail_quote"><div dir="\(wording.direction)" class="gmail_attr">\(header)<br></div><br>\
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

/// A file added to a message being written.
public struct DraftAttachment: Identifiable, Hashable, Codable, Sendable {
    public enum Content: Hashable, Codable, Sendable {
        case data(Data)
        /// A file on a message the provider holds, such as one being forwarded. Fetched when the message goes.
        case forwarded(Attachment, in: Message.ID)
        /// A whole message the provider holds, sent as `message/rfc822`, of about `size` bytes. Fetched when the
        /// message goes.
        case message(Message.ID, size: Int)
    }

    public let id: UUID
    public var filename: String
    public var mimeType: String
    public var content: Content

    public init(id: UUID = UUID(), filename: String, mimeType: String, content: Content) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.content = content
    }

    public init(id: UUID = UUID(), filename: String, mimeType: String, data: Data) {
        self.init(id: id, filename: filename, mimeType: mimeType, content: .data(data))
    }

    /// The file's bytes once they are here.
    public var data: Data? {
        if case .data(let data) = content { data } else { nil }
    }

    public var size: Int {
        switch content {
        case .data(let data): data.count
        case .forwarded(let attachment, _): attachment.size
        case .message(_, let size): size
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, filename, mimeType, content, data
    }

    /// Attachments queued before forwarding existed carry their bytes under `data`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            filename: try container.decode(String.self, forKey: .filename),
            mimeType: try container.decode(String.self, forKey: .mimeType),
            content: try container.decodeIfPresent(Data.self, forKey: .data).map(Content.data)
                ?? container.decode(Content.self, forKey: .content)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(filename, forKey: .filename)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(content, forKey: .content)
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

    /// Plain text as HTML, each line its own `dir="auto"` block so Hebrew lines read right to left.
    public static func lines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.isEmpty ? "<div><br></div>" : "<div dir=\"auto\">\(escape(String(line)))</div>"
        }.joined()
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
