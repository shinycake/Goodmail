import Foundation

/// A conversation read as a chat: each message's new words as a bubble, in time order, in runs by sender, with a
/// timestamp wherever the conversation paused. Mail too long or too laid out for a bubble stays a letter to open.
public struct ChatTranscript: Equatable, Sendable {
    public enum Side: Equatable, Sendable {
        /// Sent by this account, on the trailing side.
        case mine
        case theirs
    }

    public enum Entry: Equatable, Sendable {
        /// The time the messages below were sent, at the start and after each pause.
        case timestamp(Date)
        case run(Run)
    }

    /// Back-to-back bubbles from one sender, drawn together under one name and beside one avatar.
    public struct Run: Equatable, Sendable {
        public let side: Side
        public let sender: Contact
        public fileprivate(set) var bubbles: [Bubble]
    }

    public struct Bubble: Identifiable, Equatable, Sendable {
        public struct ID: Hashable, Sendable {
            public let message: Message.ID
            /// The attachment the bubble shows, or nil for the message's words.
            public let attachment: Attachment.ID?
        }

        public var id: ID { ID(message: message, attachment: content.attachment?.id) }
        public let message: Message.ID
        public let content: Content
    }

    public enum Content: Equatable, Sendable {
        /// The message's new words, and the earlier message it answers when that isn't the one just above.
        case words([ReplyText.Segment], replyingTo: Quote?)
        /// A message that opens in full: a long one, a laid-out one such as a newsletter, or a forward.
        case letter(subject: String, preview: String)
        case attachment(Attachment)

        var attachment: Attachment? {
            if case .attachment(let attachment) = self { attachment } else { nil }
        }
    }

    /// The earlier message a reply answers, shown above it.
    public struct Quote: Equatable, Sendable {
        public let message: Message.ID
        public let sender: Contact
        /// Whose side the quoted message is on, so a quote of the reader's own words names them as the reader.
        public let side: Side
        public let excerpt: String

        public init(message: Message.ID, sender: Contact, side: Side, excerpt: String) {
            self.message = message
            self.sender = sender
            self.side = side
            self.excerpt = excerpt
        }
    }

    public let entries: [Entry]
    /// Whether more than one other person takes part, so their bubbles need names.
    public let isGroup: Bool

    /// A pause this long puts a timestamp between messages and ends the run.
    public static let pause: TimeInterval = 60 * 60
    /// New words longer than this make a letter, not a bubble.
    static let longestBubble = 1000

    /// Unsent drafts are left out: they are the reader's to finish, not part of the conversation yet.
    public init(messages: [Message], accountEmail: String) {
        let sent = messages.filter { !$0.labelIDs.contains(SystemLabel.draft) }
        let isMine = { (message: Message) in
            message.labelIDs.contains(SystemLabel.sent)
                || message.from.address.caseInsensitiveCompare(accountEmail) == .orderedSame
        }
        let byInternetID = Dictionary(
            sent.compactMap { message in message.internetMessageID.map { ($0, message) } },
            uniquingKeysWith: { first, _ in first })

        var entries: [Entry] = []
        var previous: Message?
        for message in sent {
            let side: Side = isMine(message) ? .mine : .theirs
            let paused = previous.map { message.date.timeIntervalSince($0.date) >= Self.pause } ?? true
            if paused { entries.append(.timestamp(message.date)) }
            let parent = message.references.last.flatMap { byInternetID[$0] }
            let quote = parent.flatMap { parent in
                parent.id == previous?.id ? nil : Self.quote(of: parent, side: isMine(parent) ? .mine : .theirs)
            }
            let bubbles = Self.bubbles(for: message, replyingTo: quote)
            if !paused, case .run(var run) = entries.last, run.side == side,
                run.sender.address.caseInsensitiveCompare(message.from.address) == .orderedSame
            {
                run.bubbles += bubbles
                entries[entries.count - 1] = .run(run)
            } else {
                entries.append(.run(Run(side: side, sender: message.from, bubbles: bubbles)))
            }
            previous = message
        }
        self.entries = entries

        // Me is the account, and any address it sent from, such as an alias.
        let me = Set([accountEmail] + sent.filter(isMine).map(\.from.address)).map { $0.lowercased() }
        let others = Set(
            sent.flatMap { [$0.from] + $0.to + $0.cc }.map { $0.address.lowercased() }.filter { !me.contains($0) })
        isGroup = others.count > 1
    }

    private static func bubbles(for message: Message, replyingTo quote: Quote?) -> [Bubble] {
        let files = message.attachments.filter { !$0.isInline }.map {
            Bubble(message: message.id, content: .attachment($0))
        }
        let reply = ReplyText(body: message.body)
        let words: Content?
        if isLaidOut(message.body) || reply.text.count > longestBubble {
            words = .letter(subject: message.subject, preview: reply.text.isEmpty ? message.snippet : reply.text)
        } else if !reply.segments.isEmpty {
            words = .words(reply.segments, replyingTo: quote)
        } else if files.isEmpty {
            words = .letter(subject: message.subject, preview: message.snippet)
        } else {
            words = nil
        }
        return (words.map { [Bubble(message: message.id, content: $0)] } ?? []) + files
    }

    /// Nested tables lay out newsletters and receipts, which read as pages, not as lines of a chat.
    private static func isLaidOut(_ body: MessageBody) -> Bool {
        guard let html = body.html else { return false }
        return html.ranges(of: /(?i)<table\b/).count >= 2
    }

    private static func quote(of message: Message, side: Side) -> Quote {
        let reply = ReplyText(body: message.body)
        let firstLine =
            (reply.text.isEmpty ? message.snippet : reply.text)
            .split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return Quote(message: message.id, sender: message.from, side: side, excerpt: String(firstLine.prefix(140)))
    }
}
