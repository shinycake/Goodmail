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

        /// What takes the change back.
        public var inverse: Kind {
            switch self {
            case .archive: .moveToInbox
            case .moveToInbox: .archive
            case .trash: .untrash
            case .untrash: .trash
            case .markRead(let read): .markRead(!read)
            case .pin(let pinned): .pin(!pinned)
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
    public func inverse(madeAt: Date) -> WristCommand {
        WristCommand(threads: threads, kind: kind.inverse, madeAt: madeAt)
    }
}
