import MailCore
import UIKit

nonisolated extension SwipeChoice {
    /// The command whose keys the choice's button names in its tooltip.
    var command: MailCommand {
        switch self {
        case .read: .markRead
        case .star: .star
        case .archive: .archive
        case .snooze: .snooze
        case .trash: .trash
        case .spam: .reportSpam
        }
    }
}

/// A quick action on a row under the pointer: what its button looks like, and what it does to that row alone.
struct HoverAction {
    /// What the button shows, apart from what it does, so a row whose faces are unchanged keeps its buttons.
    nonisolated struct Face: Equatable {
        let title: String
        let symbol: String
        let tooltip: String
        /// The action's own color, which the glyph lights up in under the pointer: the color its full swipe fills with.
        let color: UIColor

        init(title: String, symbol: String, choice: SwipeChoice) {
            self.title = title
            self.symbol = symbol
            tooltip = Self.tooltip(title: title, command: choice.command)
            color = choice.color
        }

        /// The action's name with the command's keys, as "Archive ⌃⌘A"; the name alone for a command without keys.
        static func tooltip(title: String, command: MailCommand) -> String {
            command.keys.chord.map { "\(title) \($0)" } ?? title
        }
    }

    let face: Face
    let run: () -> Void
}
