public import Foundation

/// Everything a filter, a sort or a rule can ask about one mail: a cached message, or a conversation only listed so
/// far. What a listed conversation can't know, as its recipients or body, answers `nil`, and a condition on it is
/// unknown rather than false (`MailCondition.evaluate`).
public struct MailFacts: Equatable, Sendable {
    /// What every mail in a list knows.
    public struct Envelope: Equatable, Sendable {
        public var account: Account
        public var thread: ThreadSummary.ID
        public var subject: String
        public var snippet: String
        public var sender: Contact
        public var date: Date
        public var labelIDs: Set<String>
        /// How many messages the conversation holds.
        public var messageCount: Int

        public init(
            account: Account, thread: ThreadSummary.ID, subject: String, snippet: String, sender: Contact, date: Date,
            labelIDs: Set<String>, messageCount: Int
        ) {
            self.account = account
            self.thread = thread
            self.subject = subject
            self.snippet = snippet
            self.sender = sender
            self.date = date
            self.labelIDs = labelIDs
            self.messageCount = messageCount
        }
    }

    /// What a message cached on the device adds.
    public struct Content: Equatable, Sendable {
        public var id: Message.ID
        public var to: [Contact]
        public var cc: [Contact]
        public var bcc: [Contact]
        public var replyTo: [Contact]
        /// The body as plain text, as the store keeps it for search.
        public var bodyText: String
        /// The files the message carries, without the pictures its body shows inline.
        public var attachments: [Attachment]
        /// The pictures the body shows inline, which Get Attachments hands over only when asked.
        public var inlineAttachments: [Attachment]
        public var unsubscribe: Unsubscribe?
        public var internetMessageID: String?
        public var references: [String]

        public init(_ message: Message, bodyText: String) {
            id = message.id
            to = message.to
            cc = message.cc
            bcc = message.bcc
            replyTo = message.replyTo
            self.bodyText = bodyText
            attachments = message.attachments.filter { !$0.isInline }
            inlineAttachments = message.attachments.filter(\.isInline)
            unsubscribe = message.unsubscribe
            internetMessageID = message.internetMessageID
            references = message.references
        }

        var recipients: [Contact] { to + cc + bcc }
    }

    /// What the device keeps about the conversation, which no service has.
    public struct Local: Equatable, Sendable {
        public var isPinned: Bool
        public var snooze: SnoozeState?

        public init(isPinned: Bool = false, snooze: SnoozeState? = nil) {
            self.isPinned = isPinned
            self.snooze = snooze
        }
    }

    public var envelope: Envelope
    /// `nil` for a conversation only listed so far.
    public var content: Content?
    public var local: Local
    /// The names the account's labels show under, standard mailboxes included, by label ID.
    public var labelNames: [String: String]

    public init(envelope: Envelope, content: Content?, local: Local = Local(), labelNames: [String: String] = [:]) {
        self.envelope = envelope
        self.content = content
        self.local = local
        self.labelNames = labelNames
    }

    /// A cached message of `thread`.
    public init(
        message: Message, bodyText: String, thread: ThreadSummary, account: Account, local: Local = Local(),
        labelNames: [String: String] = [:]
    ) {
        let envelope = Envelope(
            account: account, thread: thread.id, subject: message.subject, snippet: message.snippet,
            sender: message.from, date: message.date, labelIDs: message.labelIDs, messageCount: thread.messageCount)
        self.init(
            envelope: envelope, content: Content(message, bodyText: bodyText), local: local, labelNames: labelNames)
    }

    /// A conversation as the list shows it, from its latest message.
    public init(
        thread: ThreadSummary, account: Account, local: Local = Local(), labelNames: [String: String] = [:]
    ) {
        let envelope = Envelope(
            account: account, thread: thread.id, subject: thread.subject, snippet: thread.snippet,
            sender: thread.sender, date: thread.date, labelIDs: thread.labelIDs, messageCount: thread.messageCount)
        self.init(envelope: envelope, content: nil, local: local, labelNames: labelNames)
    }

    // MARK: - Answering fields

    /// The field's values, or `nil` when the mail can't know them.
    public func texts(_ field: TextField) -> [String]? {
        switch field {
        case .subject: [envelope.subject]
        case .snippet: [envelope.snippet]
        case .sender: Self.words(of: [envelope.sender])
        case .senderName: [envelope.sender.name ?? ""]
        case .senderAddress: [envelope.sender.address]
        case .senderDomain: [Self.domain(of: envelope.sender.address)]
        case .mailbox: envelope.labelIDs.compactMap { labelNames[$0] }.sorted()
        case .account: [envelope.account.email]
        case .body: content.map { [$0.bodyText] }
        case .to: content.map { Self.words(of: $0.to) }
        case .cc: content.map { Self.words(of: $0.cc) }
        case .bcc: content.map { Self.words(of: $0.bcc) }
        case .replyTo: content.map { Self.words(of: $0.replyTo) }
        case .recipients: content.map { Self.words(of: $0.recipients) }
        case .attachmentName: content.map { $0.attachments.map(\.filename) }
        case .attachmentType: content.map { $0.attachments.map(\.mimeType) }
        case .unsubscribe: content.map { $0.unsubscribe.map { [$0.target] } ?? [] }
        case .internetMessageID: content.map { $0.internetMessageID.map { [$0] } ?? [] }
        }
    }

    /// The field's value, or `nil` when the mail can't know it or has none, as a body that names no amount.
    public func number(_ field: NumberField) -> Double? {
        switch field {
        case .messageCount: return Double(envelope.messageCount)
        case .toCount: return content.map { Double($0.to.count) }
        case .ccCount: return content.map { Double($0.cc.count) }
        case .bccCount: return content.map { Double($0.bcc.count) }
        case .recipientCount: return content.map { Double($0.recipients.count) }
        case .attachmentCount: return content.map { Double($0.attachments.count) }
        case .attachmentSize: return content.map { Double($0.attachments.reduce(0) { $0 + $1.size }) }
        case .bodyLength: return content.map { Double($0.bodyText.count) }
        case .largestAmount:
            guard let text = content?.bodyText else { return nil }
            return MoneyAmount.all(in: text).map(\.value).max().map { NSDecimalNumber(decimal: $0).doubleValue }
        case .totalAmount:
            guard let text = content?.bodyText, let total = MoneyAmount.total(in: text) else { return nil }
            return NSDecimalNumber(decimal: total.value).doubleValue
        }
    }

    public func date(_ field: DateField) -> Date? {
        switch field {
        case .date: envelope.date
        case .snoozedUntil:
            if case .asleep(let until) = local.snooze { until } else { nil }
        }
    }

    /// Whether the mail is so, or `nil` when it can't know.
    public func flag(_ flag: MailFlag) -> Bool? {
        let labels = envelope.labelIDs
        switch flag {
        case .unread: return labels.contains(SystemLabel.unread)
        case .starred: return labels.contains(SystemLabel.starred)
        case .important: return labels.contains(SystemLabel.important)
        case .inInbox: return labels.contains(SystemLabel.inbox)
        case .inSpam: return labels.contains(SystemLabel.spam)
        case .inTrash: return labels.contains(SystemLabel.trash)
        case .draft: return labels.contains(SystemLabel.draft)
        case .muted: return labels.contains(SystemLabel.muted)
        case .archived:
            return labels.isDisjoint(with: [SystemLabel.inbox, SystemLabel.spam, SystemLabel.trash])
        case .fromMe: return isOwn(envelope.sender.address) || labels.contains(SystemLabel.sent)
        case .forward: return Self.forwardPrefix.prefixMatch(in: envelope.subject)
        case .pinned: return local.isPinned
        case .snoozed:
            if case .asleep = local.snooze { return true } else { return false }
        case .reply:
            guard let content else { return Self.replyPrefix.prefixMatch(in: envelope.subject) }
            return !content.references.isEmpty || Self.replyPrefix.prefixMatch(in: envelope.subject)
        case .toMe: return content.map { $0.to.contains { isOwn($0.address) } }
        case .hasAttachments: return content.map { !$0.attachments.isEmpty }
        case .hasUnsubscribe: return content.map { $0.unsubscribe != nil }
        }
    }

    /// The Inbox tab the mail is in, or `nil` outside the Inbox.
    public var category: InboxCategory? {
        guard envelope.labelIDs.contains(SystemLabel.inbox) else { return nil }
        return InboxCategory.allCases.first { $0 != .primary && envelope.labelIDs.contains($0.labelID) } ?? .primary
    }

    private func isOwn(_ address: String) -> Bool {
        let own = [envelope.account.email] + envelope.account.aliases.map(\.address)
        return own.contains { $0.caseInsensitiveCompare(address) == .orderedSame }
    }

    private static func words(of contacts: [Contact]) -> [String] {
        contacts.flatMap { [$0.name, $0.address].compactMap(\.self) }
    }

    static func domain(of address: String) -> String {
        address.split(separator: "@").last.map { String($0).lowercased() } ?? ""
    }

    private static let replyPrefix = SubjectPrefix(["re", "aw", "sv", "תגובה"])
    private static let forwardPrefix = SubjectPrefix(["fwd", "fw", "wg", "הועבר"])
}

/// The words a subject starts with to say it answers or forwards another, as "Re:" or "Fwd:".
private struct SubjectPrefix: Sendable {
    let words: [String]

    init(_ words: [String]) { self.words = words }

    func prefixMatch(in subject: String) -> Bool {
        let start = subject.trimmingCharacters(in: .whitespaces).lowercased()
        return words.contains { start.hasPrefix($0 + ":") }
    }
}

extension Unsubscribe {
    /// The link or address it goes to.
    var target: String {
        switch self {
        case .oneClick(let url), .page(let url): url.absoluteString
        case .mail(let mailto): mailto.to.joined(separator: ", ")
        }
    }
}

extension SystemLabel {
    /// Gmail's Important marker.
    public static let important = "IMPORTANT"
}
