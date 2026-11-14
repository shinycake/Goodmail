import Foundation

/// How a conversation reads: as letters, one card per message, or as a chat of bubbles.
public enum ConversationLayout: String, CaseIterable, Sendable {
    case classic
    case chat

    var title: String {
        switch self {
        case .classic:
            String(
                localized: "Classic", table: "Settings", bundle: .module,
                comment: "Conversation layout: each message as a letter")
        case .chat:
            String(
                localized: "Chat", table: "Settings", bundle: .module,
                comment: "Conversation layout: messages as chat bubbles")
        }
    }

    /// The other layout, which the reader's toolbar switches one conversation to.
    var other: ConversationLayout {
        switch self {
        case .classic: .chat
        case .chat: .classic
        }
    }
}
