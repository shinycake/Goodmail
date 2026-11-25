import Foundation
import MailCore

/// The chat transcript being worked out off the main actor. A newer request overtakes the one in flight, so a
/// transcript of older messages or an older queue never replaces a newer one. It takes over the synced copies of my
/// replies the overtaken requests found, since `PendingReplies` reports each copy only once.
nonisolated enum TranscriptWork: Equatable {
    case idle
    /// `request` is the newest; `copies` open as cards once it shows.
    case working(request: UUID, copies: Set<Message.ID>)

    /// Starts a request that found `copies`, overtaking the one in flight, and returns it.
    mutating func start(copies: Set<Message.ID>) -> UUID {
        let request = UUID()
        switch self {
        case .idle: self = .working(request: request, copies: copies)
        case .working(_, let carried): self = .working(request: request, copies: carried.union(copies))
        }
        return request
    }

    /// Ends `request`: the copies to open as it shows, or `nil` when a newer request overtook it and shows instead.
    mutating func finish(_ request: UUID) -> Set<Message.ID>? {
        guard case .working(let newest, let copies) = self, newest == request else { return nil }
        self = .idle
        return copies
    }
}
