public import MailCore
public import UIKit

/// What a command would do on a screen now (ADR-034).
public enum CommandAnswer {
    /// Not something this screen does: the next screen, then the window, is asked.
    case notHere
    /// The screen's command, which it can't do now, as Move to Trash in Trash: the menu shows it dimmed, and no screen
    /// behind is asked.
    case unavailable
    /// Like `unavailable`, with the title the dimmed item shows, as a mailbox's name for Move To while it refuses.
    case refused(title: String)
    /// Ready, with the title the menu shows now when it differs from the command's own, as "Mark as Read" against
    /// "Mark as Unread", and whether the menu checks it, as the category on show.
    case ready(perform: () -> Void, title: String? = nil, isOn: Bool = false)

    /// Ready to `perform` when there is something to perform, else unavailable.
    static func offering(_ perform: (() -> Void)?, title: String? = nil) -> CommandAnswer {
        perform.map { .ready(perform: $0, title: title) } ?? .unavailable
    }
}

/// A screen that answers commands from the menu bar and the keyboard.
@MainActor
public protocol CommandScreen: UIViewController {
    func answer(to command: MailCommand) -> CommandAnswer
}

/// Finds which screen answers each command: a presented screen, as the composer, alone, since it covers the rest;
/// otherwise the shown screens from the front, the thread before its list before the mailboxes.
@MainActor
public enum CommandRouting {
    /// The frontmost answer other than `.notHere` among the screens on show, or `.notHere` when none has the command.
    public static func answer(to command: MailCommand, in root: UIViewController?) -> CommandAnswer {
        for screen in screens(in: root) {
            let answer = screen.answer(to: command)
            if case .notHere = answer { continue }
            return answer
        }
        return .notHere
    }

    /// Key commands for the keyed commands `answer` says are ready now, under the titles it gives, each performing
    /// through `action`.
    public static func keyCommands(action: Selector, answer: (MailCommand) -> CommandAnswer) -> [UIKeyCommand] {
        MailCommand.allCases.compactMap { command in
            guard let chord = command.keys.chord, case .ready(_, let title, _) = answer(command) else { return nil }
            return command.keyCommand(chord, title: title, action: action)
        }
    }

    static func screens(in root: UIViewController?) -> [any CommandScreen] {
        guard let root else { return [] }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return shown(in: top)
    }

    /// The screens `controller` shows, frontmost first.
    private static func shown(in controller: UIViewController) -> [any CommandScreen] {
        switch controller {
        case let screen as any CommandScreen:
            return [screen]
        case let navigation as UINavigationController:
            return navigation.topViewController.map(shown(in:)) ?? []
        case let split as UISplitViewController:
            let columns: [UISplitViewController.Column] =
                split.isCollapsed ? [.compact] : [.secondary, .supplementary, .primary]
            return columns.compactMap(split.viewController(for:)).flatMap(shown(in:))
        default:
            return controller.children.reversed().flatMap(shown(in:))
        }
    }
}
