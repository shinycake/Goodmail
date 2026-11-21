import MailCore
import UIKit

nonisolated extension SwipeArrangement {
    /// The buttons a row shows while the pointer rests on it, in the order the reader's swipes come: the left side's
    /// choices, then the right side's, each side as arranged. A choice that means nothing here is left out.
    func hoverButtons(for thread: ThreadSummary, at place: ThreadPlace, tints: SwipeTints)
        -> [MailboxViewModel.SwipeButton]
    {
        buttons(for: thread, at: place, on: .left, tints: tints)
            + buttons(for: thread, at: place, on: .right, tints: tints)
    }
}

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
            self.init(
                title: title, symbol: symbol, tooltip: Self.tooltip(title: title, command: choice.command),
                color: choice.color)
        }

        private init(title: String, symbol: String, tooltip: String, color: UIColor) {
            self.title = title
            self.symbol = symbol
            self.tooltip = tooltip
            self.color = color
        }

        /// The button that ends a capsule too narrow for every action, and opens a menu of the rest.
        static var more: Face {
            let title = String(
                localized: "More Actions", table: "Mailbox", bundle: .module,
                comment: "Hover button on a mailbox row that opens the quick actions with no room in the row")
            return Face(title: title, symbol: "ellipsis", tooltip: title, color: .label)
        }

        /// The action's name with the command's keys, as "Archive ⌃⌘A"; the name alone for a command without keys.
        static func tooltip(title: String, command: MailCommand) -> String {
            command.keys.chord.map { "\(title) \($0)" } ?? title
        }
    }

    let face: Face
    let run: () -> Void
}
