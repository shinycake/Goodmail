import MailCore

/// Which of a conversation's messages show as cards; the rest are one-line rows in the timeline. Nothing is decided
/// until the store first brings the conversation's messages or the reader opens one, and at least one card stays open
/// after.
nonisolated enum OpenCards: Equatable {
    case unset
    case open(Set<Message.ID>)

    var ids: Set<Message.ID> {
        switch self {
        case .unset: []
        case .open(let ids): ids
        }
    }

    /// The store brought `messages`. The first time there are any, its unread messages and the newest open, as they
    /// were before opening marked them read; after that the reader's choice stands.
    mutating func arrived(_ messages: [Message]) {
        guard case .unset = self, !messages.isEmpty else { return }
        self = .open(Self.initial(messages))
    }

    /// Opens `ids`, synced copies of my replies, as the cards they replace.
    mutating func open(_ ids: Set<Message.ID>) {
        guard !ids.isEmpty else { return }
        self = .open(self.ids.union(ids))
    }

    /// Opens a row as a card, or folds a card into a row unless it is the last one open.
    mutating func toggle(_ id: Message.ID) {
        var ids = self.ids
        if ids.contains(id), ids.count > 1 {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        self = .open(ids)
    }

    /// Unread messages and the newest open as cards; the rest of the history stays in the timeline.
    static func initial(_ messages: [Message]) -> Set<Message.ID> {
        Set(messages.filter(\.isUnread).map(\.id) + (messages.last.map { [$0.id] } ?? []))
    }
}
