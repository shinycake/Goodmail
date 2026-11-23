public import Foundation

/// A message of mine for this conversation that hasn't synced into it yet: on its way, waiting for its time, failed,
/// or gone but not yet back from the server. One on its way reads as sent until it is overdue. The chat draws it as
/// my bubble at the end, and the classic layout as my letter there, with how far it got.
public struct PendingReply: Identifiable, Equatable, Sendable {
    public var id: Draft.ID { draft.id }
    public let draft: Draft
    /// The address it goes from: the account's, or the alias the draft picked.
    public let sender: Contact
    /// When it goes, or went: the end of its undo window, or its scheduled time.
    public let date: Date
    /// The `Message-ID` it goes out with, which its synced copy carries, unless the server gives it one of its own.
    let headerID: String
    /// How far it got.
    public let phase: Phase
    /// How it reads as of the update that made it: what `phase` means at that time.
    public let delivery: ChatTranscript.Delivery

    /// How far a reply got. Only the queue moves it on, through `PendingReplies.update`.
    public enum Phase: Equatable, Sendable {
        /// Waiting under Scheduled until this time.
        case scheduled(Date)
        /// In its undo window, or waiting to be sent. It reads as sent until `overdueAt`, then as still sending.
        case onItsWay(overdueAt: Date)
        /// Handed to a transfer that outlives the app, its answer still to come. It reads as `onItsWay` does.
        case handedOver(overdueAt: Date)
        /// Failed for good, until the writer tries again, edits it or deletes it.
        case failed(SendFailure)
        /// It left the queue without being taken back, so it went; it stays until its copy syncs.
        case gone
    }

    /// How long after its time a reply may take to go before it shows as still sending. Until then it reads as sent,
    /// as a chat's does the moment it is sent: the undo toast is there to take it back, and a send takes a moment.
    public static let overdueAfter: TimeInterval = 5

    public init(_ message: OutgoingMessage, accountEmail: String, now: Date) {
        let phase: Phase =
            switch message.delivery {
            case .failed(let failure): .failed(failure)
            case .queued where message.purpose == .scheduledSend && message.sendAt > now: .scheduled(message.sendAt)
            case .queued: .onItsWay(overdueAt: message.sendAt.addingTimeInterval(Self.overdueAfter))
            case .uploading: .handedOver(overdueAt: message.sendAt.addingTimeInterval(Self.overdueAfter))
            }
        self.init(
            draft: message.draft, sender: message.draft.alias ?? Contact(name: nil, address: accountEmail),
            date: message.sendAt, headerID: message.headerID, phase: phase, now: now)
    }

    private init(draft: Draft, sender: Contact, date: Date, headerID: String, phase: Phase, now: Date) {
        self.draft = draft
        self.sender = sender
        self.date = date
        self.headerID = headerID
        self.phase = phase
        delivery =
            switch phase {
            case .scheduled(let date): .scheduled(date)
            case .onItsWay(let overdueAt), .handedOver(let overdueAt): now < overdueAt ? .sent : .sending
            case .failed(let failure): .failed(failure)
            case .gone: .sent
            }
    }

    /// This reply once it left the queue without being taken back.
    fileprivate var gone: PendingReply {
        PendingReply(draft: draft, sender: sender, date: date, headerID: headerID, phase: .gone, now: date)
    }

    /// Whether it waits for a later time, so it sits after everything that goes now.
    var isScheduled: Bool {
        if case .scheduled = phase { true } else { false }
    }

    /// Whether it may have reached the server: it went, or a transfer carries it. One in its undo window, waiting for
    /// its time or to be sent, or failed, has no copy anywhere.
    fileprivate var isHandedOver: Bool {
        switch phase {
        case .gone, .handedOver: true
        case .scheduled, .onItsWay, .failed: false
        }
    }

    /// The words it adds, as its synced copy reads them, with the spacing the copy's HTML may change left out.
    fileprivate var words: String {
        Self.words(of: draft.body)
    }

    fileprivate static func words(of body: MessageBody) -> String {
        ReplyText(body: body).text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The times after `now` its delivery changes on its own: when a scheduled reply goes, and when it is overdue.
    fileprivate func changes(after now: Date) -> [Date] {
        let changes =
            switch phase {
            case .scheduled(let date): [date, date.addingTimeInterval(Self.overdueAfter)]
            case .onItsWay(let overdueAt), .handedOver(let overdueAt): [overdueAt]
            case .failed, .gone: [Date]()
            }
        return changes.filter { $0 > now }
    }
}

/// The conversation's replies still on their way, worked out from the outgoing queue and the synced messages.
///
/// A message leaves the queue in one of two ways: the writer took it back (undo, edit, delete), or it went. One that
/// went stays here as sent until its copy syncs into the conversation, so its bubble never blinks out in between.
///
/// A copy is known by the `Message-ID` its reply went out with. Gmail's API sends under a `Message-ID` of its own,
/// so a reply that has gone, or is being carried, is also known by what it says: a message of mine dated from its
/// time on (`copySkew` before, for the clocks) that answers the same message with the same words. A reply that
/// answers nothing is known only by its `Message-ID`.
public struct PendingReplies: Equatable, Sendable {
    public private(set) var replies: [PendingReply] = []
    /// Synced copies that took the place of replies shown before the last update.
    public private(set) var copies: [Message.ID] = []

    /// How much earlier than its reply's time a copy may be dated, as the server's clock and the device's differ.
    static let copySkew: TimeInterval = 60

    public init() {}

    /// The one transition: `queue` is the outgoing queue for this conversation, `takenBack` the messages the writer
    /// took back, and `conversation` its synced messages.
    public mutating func update(
        queue: [OutgoingMessage], takenBack: Set<Draft.ID>, conversation: [Message], accountEmail: String, now: Date
    ) {
        let queued = Set(queue.map(\.id))
        let onTheirWay = queue.filter { [.send, .scheduledSend].contains($0.purpose) }
            .map { PendingReply($0, accountEmail: accountEmail, now: now) }
        let went = replies.filter { !queued.contains($0.id) && !takenBack.contains($0.id) }.map(\.gone)
        let candidates = onTheirWay + went
        let paired = Self.pairs(of: candidates, in: conversation)
        let shown = Set(replies.map(\.id))
        let copied = Set(paired.filter { shown.contains($0.key) }.values)
        copies = conversation.map(\.id).filter(copied.contains)
        replies = candidates.filter { paired[$0.id] == nil }.sorted { first, second in
            first.isScheduled == second.isScheduled ? first.date < second.date : !first.isScheduled
        }
    }

    /// The next time after `now` a reply's delivery changes with no change to the queue, for the chat to update
    /// then; `nil` when none will.
    public func nextChange(after now: Date) -> Date? {
        replies.flatMap { $0.changes(after: now) }.min()
    }

    /// Each reply's synced copy in `conversation`, where it has one: the message carrying its `Message-ID`, or else,
    /// for a reply handed over, the first message of mine from its time on answering what it answers with its words.
    /// Saved drafts are never copies. The replies take copies in the order of their times, so two that say the same
    /// to one message each get their own.
    private static func pairs(of replies: [PendingReply], in conversation: [Message]) -> [Draft.ID: Message.ID] {
        let sent = conversation.filter { !$0.labelIDs.contains(SystemLabel.draft) }
        let byHeader = Dictionary(
            sent.compactMap { message in message.internetMessageID.map { (bare($0), message.id) } },
            uniquingKeysWith: { first, _ in first })
        var pairs: [Draft.ID: Message.ID] = [:]
        for reply in replies {
            pairs[reply.id] = byHeader[reply.headerID]
        }
        var taken = Set(pairs.values)
        for reply in replies.sorted(by: { $0.date < $1.date }) where pairs[reply.id] == nil && reply.isHandedOver {
            guard let answers = reply.draft.references.last.map(bare) else { continue }
            let copy = sent.first { message in
                !taken.contains(message.id) && message.date >= reply.date.addingTimeInterval(-copySkew)
                    && isMine(message, sentAs: reply) && message.references.last.map(bare) == answers
                    && PendingReply.words(of: message.body) == reply.words
            }
            if let copy {
                pairs[reply.id] = copy.id
                taken.insert(copy.id)
            }
        }
        return pairs
    }

    /// Whether the account sent `message`, as it sends `reply`: it sits in Sent, or comes from the reply's address.
    private static func isMine(_ message: Message, sentAs reply: PendingReply) -> Bool {
        message.labelIDs.contains(SystemLabel.sent)
            || message.from.address.caseInsensitiveCompare(reply.sender.address) == .orderedSame
    }

    /// A `Message-ID` without the angle brackets some headers keep.
    private static func bare(_ id: String) -> String {
        id.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }
}
