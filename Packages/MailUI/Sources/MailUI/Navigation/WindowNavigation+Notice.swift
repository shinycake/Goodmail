import Foundation
public import MailCore

extension WindowNavigation.Notice {
    /// What the window says, in the toast along its bottom.
    public var text: String {
        switch self {
        case .conversationGone:
            String(
                localized: "That conversation is no longer available.", table: "Navigation", bundle: .module,
                comment: "Toast when a tapped alert, Spotlight result or Shortcut opens a conversation that was deleted"
            )
        case .conversationUnreachable:
            String(
                localized: "That conversation couldn't be opened. Check your connection and try again.",
                table: "Navigation", bundle: .module,
                comment:
                    "Toast when a tapped alert, Spotlight result or Shortcut opens a conversation not yet on this device while the server can't be reached"
            )
        }
    }
}
