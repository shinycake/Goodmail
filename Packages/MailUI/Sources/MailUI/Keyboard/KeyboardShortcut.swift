public import UIKit

/// A command a hardware keyboard reaches, with the keys Apple Mail gives it, so the app works with Full Keyboard
/// Access and a keyboard on iPad without a finger on the screen. Holding Command lists them.
public nonisolated enum KeyboardShortcut: String, CaseIterable, Sendable {
    case newMessage
    case getMail
    case search
    case reply
    case replyAll
    case forward
    case archive
    case trash
    case markUnread
    case star
    case send
    case previousThread
    case nextThread
    /// Answered by the window rather than a screen (`WindowCommands`).
    case newWindow
    case closeWindow
    case settings

    var input: String {
        switch self {
        case .newMessage, .getMail, .newWindow: "n"
        case .search, .forward: "f"
        case .reply, .replyAll: "r"
        case .archive: "a"
        case .trash: UIKeyCommand.inputDelete
        case .markUnread: "u"
        case .star: "l"
        case .send: "d"
        case .previousThread: UIKeyCommand.inputUpArrow
        case .nextThread: UIKeyCommand.inputDownArrow
        case .closeWindow: "w"
        case .settings: ","
        }
    }

    var modifiers: UIKeyModifierFlags {
        switch self {
        case .newMessage, .reply, .trash, .closeWindow, .settings: .command
        case .getMail, .replyAll, .forward, .markUnread, .star, .send: [.command, .shift]
        case .search, .newWindow: [.command, .alternate]
        case .archive, .previousThread, .nextThread: [.command, .control]
        }
    }
}

/// A screen that answers keyboard shortcuts.
@MainActor
public protocol KeyboardShortcutScreen: UIViewController {
    /// What `shortcut` does here now, or `nil` when it does nothing here, as Reply in a list.
    func action(for shortcut: KeyboardShortcut) -> (() -> Void)?
}

/// Finds which screen answers each shortcut: a presented screen, as the composer, alone, since it covers the rest;
/// otherwise the shown screens from the front, the thread before its list before the mailboxes.
@MainActor
public enum KeyboardShortcuts {
    /// The key commands the window offers now, each performing through `action` on the window.
    public static func commands(in root: UIViewController?, action: Selector) -> [UIKeyCommand] {
        let screens = screens(in: root)
        return KeyboardShortcut.allCases.compactMap { shortcut in
            guard screens.contains(where: { $0.action(for: shortcut) != nil }) else { return nil }
            return shortcut.command(action: action)
        }
    }

    /// What `shortcut` does on the frontmost screen that answers it, or `nil` when none does.
    public static func action(for shortcut: KeyboardShortcut, in root: UIViewController?) -> (() -> Void)? {
        screens(in: root).lazy.compactMap { $0.action(for: shortcut) }.first
    }

    static func screens(in root: UIViewController?) -> [any KeyboardShortcutScreen] {
        guard let root else { return [] }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        return shown(in: top)
    }

    /// The screens `controller` shows, frontmost first.
    private static func shown(in controller: UIViewController) -> [any KeyboardShortcutScreen] {
        switch controller {
        case let screen as any KeyboardShortcutScreen:
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

extension KeyboardShortcut {
    /// The shortcut a key command made by `command(action:)` stands for.
    public init?(_ command: UICommand) {
        guard let raw = command.propertyList as? String else { return nil }
        self.init(rawValue: raw)
    }

    /// A key command for the shortcut, performing through `action`.
    func command(action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(
            title: title, action: action, input: input, modifierFlags: modifiers, propertyList: rawValue)
        // Delete edits text first, where the composer's field has the keyboard, and the arrows move its caret.
        command.wantsPriorityOverSystemBehavior = ![.trash, .previousThread, .nextThread].contains(self)
        return command
    }

    /// The command's name in the list Command shows, and for Full Keyboard Access.
    var title: String {
        switch self {
        case .newMessage:
            String(localized: "New Message", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .getMail:
            String(localized: "Get New Mail", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .search:
            String(localized: "Search Mail", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .reply: String(localized: "Reply", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .replyAll:
            String(localized: "Reply All", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .forward: String(localized: "Forward", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .archive: String(localized: "Archive", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .trash:
            String(localized: "Move to Trash", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .markUnread:
            String(localized: "Mark as Unread", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .star:
            String(localized: "Star or Unstar", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .send: String(localized: "Send", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .previousThread:
            String(localized: "Previous Message", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .nextThread:
            String(localized: "Next Message", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .newWindow:
            String(localized: "New Window", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .closeWindow:
            String(localized: "Close Window", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        case .settings:
            String(localized: "Settings…", table: "Keyboard", bundle: .module, comment: "Keyboard command")
        }
    }
}
