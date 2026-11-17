public import Foundation
public import MailCore

/// A change the reader makes on the watch, which the iPhone carries out through `MailCommands` (ADR-022). Each has an
/// ID, so the iPhone runs it once however often it arrives, and the watch knows when the iPhone's Inbox includes it.
public struct WristCommand: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case archive
        case moveToInbox
        case trash
        case untrash
        case markRead(Bool)
        case pin(Bool)
        /// Sends these words as a reply to the conversation's newest message.
        case reply(String)
        /// Takes the conversations out of the Inbox until the date, when they come back.
        case snooze(until: Date)
        /// Ends a snooze now, putting the conversations back in the Inbox. Only Undo sends it.
        case unsnooze

        /// What takes the change back; `nil` for a reply, which can't be taken back once sent. The watch holds a
        /// reply for a moment before sending it instead.
        public var inverse: Kind? {
            switch self {
            case .archive: .moveToInbox
            case .moveToInbox: .archive
            case .trash: .untrash
            case .untrash: .trash
            case .markRead(let read): .markRead(!read)
            case .pin(let pinned): .pin(!pinned)
            case .snooze: .unsnooze
            case .reply, .unsnooze: nil
            }
        }
    }

    public var id: UUID
    public var threads: [ThreadSummary.ID]
    public var kind: Kind
    public var madeAt: Date

    public init(id: UUID = UUID(), threads: [ThreadSummary.ID], kind: Kind, madeAt: Date) {
        self.id = id
        self.threads = threads
        self.kind = kind
        self.madeAt = madeAt
    }

    /// A new command that takes this one back, as Undo sends.
    public func inverse(madeAt: Date) -> WristCommand? {
        kind.inverse.map { WristCommand(threads: threads, kind: $0, madeAt: madeAt) }
    }
}
