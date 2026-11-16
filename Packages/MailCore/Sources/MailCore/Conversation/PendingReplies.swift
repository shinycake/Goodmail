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
    /// The `Message-ID` it goes out with, which its synced copy carries.
    let headerID: String
    /// How far it got.
    public let phase: Phase
    /// How it reads as of the update that made it: what `phase` means at that time.
    public let delivery: ChatTranscript.Delivery

    /// How far a reply got. Only the queue moves it on, through `PendingReplies.update`.
    public enum Phase: Equatable, Sendable {
        /// Waiting under Scheduled until this time.
        case scheduled(Date)
        /// In its undo window or being sent. It reads as sent until `overdueAt`, then as still sending.
        case onItsWay(overdueAt: Date)
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
            case .queued, .uploading: .onItsWay(overdueAt: message.sendAt.addingTimeInterval(Self.overdueAfter))
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
            case .onItsWay(let overdueAt): now < overdueAt ? .sent : .sending
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

    /// The times after `now` its delivery changes on its own: when a scheduled reply goes, and when it is overdue.
    fileprivate func changes(after now: Date) -> [Date] {
        let changes =
            switch phase {
            case .scheduled(let date): [date, date.addingTimeInterval(Self.overdueAfter)]
            case .onItsWay(let overdueAt): [overdueAt]
            case .failed, .gone: [Date]()
            }
        return changes.filter { $0 > now }
    }
}

/// The conversation's replies still on their way, worked out from the outgoing queue and the synced messages.
///
/// A message leaves the queue in one of two ways: the writer took it back (undo, edit, delete), or it went. One that
/// went stays here as sent until its copy syncs into the conversation, so its bubble never blinks out in between.
public struct PendingReplies: Equatable, Sendable {
    public private(set) var replies: [PendingReply] = []

    public init() {}

    /// The one transition: `queue` is the outgoing queue for this conversation, `takenBack` the messages the writer
    /// took back, and `conversation` its synced messages.
    public mutating func update(
        queue: [OutgoingMessage], takenBack: Set<Draft.ID>, conversation: [Message], accountEmail: String, now: Date
    ) {
        let synced = Set(conversation.compactMap { $0.internetMessageID.map(Self.bare) })
        let queued = Set(queue.map(\.id))
        let onTheirWay = queue.filter { message in
            [.send, .scheduledSend].contains(message.purpose) && !synced.contains(message.headerID)
        }.map { PendingReply($0, accountEmail: accountEmail, now: now) }
        let went = replies.filter { reply in
            !queued.contains(reply.id) && !takenBack.contains(reply.id) && !synced.contains(reply.headerID)
        }.map(\.gone)
        replies = (onTheirWay + went).sorted { first, second in
            first.isScheduled == second.isScheduled ? first.date < second.date : !first.isScheduled
        }
    }

    /// The messages in `conversation` that are synced copies of replies shown here, which take their place.
    public func copies(in conversation: [Message]) -> [Message.ID] {
        let shown = Set(replies.map(\.headerID))
        return conversation.filter { message in
            message.internetMessageID.map { shown.contains(Self.bare($0)) } ?? false
        }.map(\.id)
    }

    /// The next time after `now` a reply's delivery changes with no change to the queue, for the chat to update
    /// then; `nil` when none will.
    public func nextChange(after now: Date) -> Date? {
        replies.flatMap { $0.changes(after: now) }.min()
    }

    /// A `Message-ID` without the angle brackets some headers keep.
    private static func bare(_ id: String) -> String {
        id.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }
}
