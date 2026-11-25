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

        /// What a change of this kind sets on a conversation, which a later change on the same one replaces: whether
        /// it is in the Inbox, in the Trash, read, pinned or asleep. `nil` for a reply, which replaces nothing.
        public enum Aspect: String, Codable, Sendable {
            case inbox, trash, read, pin, sleep
        }

        /// What this kind of change sets.
        public var aspect: Aspect? {
            switch self {
            case .archive, .moveToInbox: .inbox
            case .trash, .untrash: .trash
            case .markRead: .read
            case .pin: .pin
            case .snooze, .unsnooze: .sleep
            case .reply: nil
            }
        }

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
    /// Who runs it (ADR-023).
    public var executor: WristExecutor
    /// When the watch handed it to the iPhone, having stamped it for itself (`WristMailbox.handToPhone`): it waits for
    /// the iPhone from then on, however long after the reader made it.
    public var handedOverAt: Date?

    public init(
        id: UUID = UUID(), threads: [ThreadSummary.ID], kind: Kind, madeAt: Date, executor: WristExecutor = .phone
    ) {
        self.id = id
        self.threads = threads
        self.kind = kind
        self.madeAt = madeAt
        self.executor = executor
    }

    private enum CodingKeys: String, CodingKey {
        case id, threads, kind, madeAt, executor, handedOverAt
    }

    /// A command from a watch that predates `executor` runs on the iPhone, as every command did then.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            threads: try container.decode([ThreadSummary.ID].self, forKey: .threads),
            kind: try container.decode(Kind.self, forKey: .kind),
            madeAt: try container.decode(Date.self, forKey: .madeAt),
            executor: try container.decodeIfPresent(WristExecutor.self, forKey: .executor) ?? .phone)
        handedOverAt = try container.decodeIfPresent(Date.self, forKey: .handedOverAt)
    }

    /// Leaves `executor` out for the iPhone, so an iPhone's command reads the same to every version.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(threads, forKey: .threads)
        try container.encode(kind, forKey: .kind)
        try container.encode(madeAt, forKey: .madeAt)
        if executor == .watch { try container.encode(executor, forKey: .executor) }
        // Only a handed-over command has it, so every other command reads the same to every version.
        try container.encodeIfPresent(handedOverAt, forKey: .handedOverAt)
    }

    /// A new command that takes this one back, as Undo sends.
    public func inverse(madeAt: Date) -> WristCommand? {
        kind.inverse.map { WristCommand(threads: threads, kind: $0, madeAt: madeAt, executor: executor) }
    }
}
