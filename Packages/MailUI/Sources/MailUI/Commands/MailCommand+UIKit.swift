public import MailCore
public import UIKit

extension MailCommand {
    /// The command a menu item or key command made here stands for.
    public init?(_ command: UICommand) {
        guard let raw = command.propertyList as? String else { return nil }
        self.init(rawValue: raw)
    }

    /// The command's menu item, with `chord` as its keys when it has them there, performing through `action`.
    func menuItem(_ chord: KeyChord?, action: Selector) -> UICommand {
        guard let chord else { return UICommand(title: title, action: action, propertyList: rawValue) }
        return keyCommand(chord, title: nil, action: action)
    }

    /// A key command for `chord`, under `title` or else the command's own, performing through `action`.
    func keyCommand(_ chord: KeyChord, title: String?, action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(
            title: title ?? self.title, action: action, input: chord.input, modifierFlags: chord.modifierFlags,
            propertyList: rawValue)
        // Delete edits text first, where a field has the keyboard, and the arrows move its caret.
        if case .character = chord.key { command.wantsPriorityOverSystemBehavior = true }
        return command
    }
}

extension KeyChord {
    var input: String {
        switch key {
        case .character(let character): String(character)
        case .delete: UIKeyCommand.inputDelete
        case .upArrow: UIKeyCommand.inputUpArrow
        case .downArrow: UIKeyCommand.inputDownArrow
        }
    }

    var modifierFlags: UIKeyModifierFlags {
        let flags: [(Modifiers, UIKeyModifierFlags)] = [
            (.command, .command), (.shift, .shift), (.option, .alternate), (.control, .control),
        ]
        return UIKeyModifierFlags(flags.filter { modifiers.contains($0.0) }.map(\.1))
    }
}

extension SystemMenuItem {
    /// The system menu that holds the item.
    var menu: UIMenu.Identifier {
        switch self {
        case .findAndReplace: .find
        case .print: .print
        case .newWindow: .newItem
        case .close: .close
        case .find, .findNext, .findPrevious: .find
        }
    }

    /// The action the system's item sends up the responder chain for the window to answer, or `nil` when the system
    /// does the work itself.
    var action: Selector? {
        switch self {
        case .findAndReplace: #selector(UIResponder.findAndReplace(_:))
        case .print: #selector(UIResponder.printContent(_:))
        case .find: #selector(UIResponder.find(_:))
        case .findNext: #selector(UIResponder.findNext(_:))
        case .findPrevious: #selector(UIResponder.findPrevious(_:))
        case .newWindow, .close: nil
        }
    }

    /// Whether the command's own item, without keys, sits in its place too: the system's item says Find and Replace,
    /// not Search Mail. The others say what the command does.
    public var keepsCommandItem: Bool { self == .findAndReplace }

    /// The item whose action is `action`.
    public init?(action: Selector) {
        guard let item = Self.allCases.first(where: { $0.action == action }) else { return nil }
        self = item
    }

    /// The command that rides on the item.
    public var command: MailCommand? {
        MailCommand.allCases.first { $0.keys == .system(self) }
    }
}

extension UICommand {
    /// Shows in the menu what `command` would do now: enabled, titled and checked as its screen says when it's ready,
    /// otherwise dimmed, under the title a refusal gives or the command's own. A number past the sidebar's last row
    /// has nothing to name, so its item goes from the menu.
    public func show(_ answer: CommandAnswer, as command: MailCommand) {
        var hidden = false
        switch answer {
        case .ready(_, let title, let isOn):
            self.title = title ?? command.title
            state = isOn ? .on : .off
        case .unavailable:
            self.title = command.title
            state = .off
        case .refused(let title):
            self.title = title
            state = .off
        case .notHere:
            self.title = command.title
            state = .off
            hidden = command.rowShortcut != nil
        }
        if case .ready = answer { attributes.remove(.disabled) } else { attributes.insert(.disabled) }
        if hidden { attributes.insert(.hidden) } else { attributes.remove(.hidden) }
    }
}
