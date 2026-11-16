public import Foundation

/// A message of mine for this conversation that hasn't synced into it yet: on its way, waiting for its time, failed,
/// or gone but not yet back from the server. The chat draws it as my bubble at the end, with how far it got.
public struct PendingReply: Identifiable, Equatable, Sendable {
    public var id: Draft.ID { draft.id }
    public let draft: Draft
    /// The address it goes from: the account's, or the alias the draft picked.
    public let sender: Contact
    /// When it goes, or went: the end of its undo window, or its scheduled time.
    public let date: Date
    /// The `Message-ID` it goes out with, which its synced copy carries.
    let headerID: String
    public fileprivate(set) var delivery: ChatTranscript.Delivery

    public init(_ message: OutgoingMessage, accountEmail: String, now: Date) {
        draft = message.draft
        sender = message.draft.alias ?? Contact(name: nil, address: accountEmail)
        date = message.sendAt
        headerID = message.headerID
        delivery =
            switch message.delivery {
            case .failed(let failure): .failed(failure)
            case .uploading: .sending
            case .queued:
                message.purpose == .scheduledSend && message.sendAt > now ? .scheduled(message.sendAt) : .sending
            }
    }

    /// Whether it waits for a later time, so it sits after everything that goes now.
    var isScheduled: Bool {
        if case .scheduled = delivery { true } else { false }
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
        }.map { reply in
            var reply = reply
            reply.delivery = .sent
            return reply
        }
        replies = (onTheirWay + went).sorted { first, second in
            first.isScheduled == second.isScheduled ? first.date < second.date : !first.isScheduled
        }
    }

    /// A `Message-ID` without the angle brackets some headers keep.
    private static func bare(_ id: String) -> String {
        id.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }
}
