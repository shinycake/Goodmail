public import Foundation

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

    /// How far a bubble of mine got on its way. Every message synced into the conversation has gone.
    public enum Delivery: Equatable, Sendable {
        /// Still on its way a while after its time (`PendingReply.overdueAfter`), as with no connection.
        case sending
        /// Waiting under Scheduled until this time.
        case scheduled(Date)
        /// Failed for good, until the writer tries again, edits it or deletes it.
        case failed(SendFailure)
        /// Gone, or on its way and not yet overdue: in its undo window, or being handed to the server.
        case sent
    }

    public struct Bubble: Identifiable, Equatable, Sendable {
        /// Where a bubble's words come from: a synced message, or a reply still on its way.
        public enum Origin: Hashable, Sendable {
            case message(Message.ID)
            case pending(Draft.ID)
        }

        public struct ID: Hashable, Sendable {
            public let origin: Origin
            /// The attachment the bubble shows, or nil for the message's words.
            public let attachment: Attachment.ID?
        }

        public var id: ID { ID(origin: origin, attachment: content.attachment?.id) }
        public let origin: Origin
        public let content: Content
        public let delivery: Delivery

        init(origin: Origin, content: Content, delivery: Delivery = .sent) {
            self.origin = origin
            self.content = content
            self.delivery = delivery
        }

        /// The synced message the bubble shows, or nil while it is still on its way.
        public var message: Message.ID? {
            if case .message(let id) = origin { id } else { nil }
        }
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
    /// Everyone else who takes part, in the order they first appear.
    public let others: [Contact]
    /// Whether more than one other person takes part, so their bubbles need names.
    public var isGroup: Bool { others.count > 1 }

    /// A pause this long puts a timestamp between messages and ends the run.
    public static let pause: TimeInterval = 60 * 60
    /// New words longer than this make a letter, not a bubble.
    static let longestBubble = 1000

    /// Unsent drafts are left out: they are the reader's to finish, not part of the conversation yet. Mine are the
    /// messages the account sent, from its own address or one of its `aliases`. My `pending` replies follow the
    /// synced messages, the ones that go now first and the scheduled ones last, without a timestamp of their own.
    public init(messages: [Message], accountEmail: String, aliases: [Contact] = [], pending: [PendingReply] = []) {
        let sent = messages.filter { !$0.labelIDs.contains(SystemLabel.draft) }
        let addresses = Set(([accountEmail] + aliases.map(\.address)).map { $0.lowercased() })
        let isMine = { (message: Message) in
            message.labelIDs.contains(SystemLabel.sent) || addresses.contains(message.from.address.lowercased())
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
            Self.append(Self.bubbles(for: message, replyingTo: quote), from: message.from, side: side, to: &entries)
            previous = message
        }
        var last = previous?.date
        for reply in pending {
            if !reply.isScheduled {
                if last.map({ reply.date.timeIntervalSince($0) >= Self.pause }) ?? true {
                    entries.append(.timestamp(reply.date))
                }
                last = reply.date
            }
            Self.append(Self.bubbles(for: reply), from: reply.sender, side: .mine, to: &entries)
        }
        self.entries = entries

        // Me is the account, and any address it sent from, such as an alias.
        let me = addresses.union(sent.filter(isMine).map { $0.from.address.lowercased() })
        var seen = me
        others = sent.flatMap { [$0.from] + $0.to + $0.cc }.filter { seen.insert($0.address.lowercased()).inserted }
    }

    /// Joins the run above when the same sender wrote it with no timestamp between, or starts a run.
    private static func append(_ bubbles: [Bubble], from sender: Contact, side: Side, to entries: inout [Entry]) {
        if case .run(var run) = entries.last, run.side == side,
            run.sender.address.caseInsensitiveCompare(sender.address) == .orderedSame
        {
            run.bubbles += bubbles
            entries[entries.count - 1] = .run(run)
        } else {
            entries.append(.run(Run(side: side, sender: sender, bubbles: bubbles)))
        }
    }

    /// A reply on its way reads as what was typed, with each file it carries.
    private static func bubbles(for reply: PendingReply) -> [Bubble] {
        let segments = ReplyText(body: reply.draft.body).segments
        let words: [Content] = segments.isEmpty ? [] : [.words(segments, replyingTo: nil)]
        let files: [Content] = reply.draft.attachments.map { file in
            .attachment(
                Attachment(id: file.id.uuidString, filename: file.filename, mimeType: file.mimeType, size: file.size))
        }
        return (words + files).map { Bubble(origin: .pending(reply.id), content: $0, delivery: reply.delivery) }
    }

    private static func bubbles(for message: Message, replyingTo quote: Quote?) -> [Bubble] {
        let origin = Bubble.Origin.message(message.id)
        let files = message.attachments.filter { !$0.isInline }.map {
            Bubble(origin: origin, content: .attachment($0))
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
        return (words.map { [Bubble(origin: origin, content: $0)] } ?? []) + files
    }

    /// Nested tables lay out newsletters and receipts, which read as pages, not as lines of a chat.
    private static func isLaidOut(_ body: MessageBody) -> Bool {
        guard let html = body.markup else { return false }
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
