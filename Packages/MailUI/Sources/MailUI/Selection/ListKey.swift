import UIKit

/// The keys a desktop window's list answers while it has the keyboard, as in Apple Mail. ⌘A is Edit > Select All's,
/// which reaches the list as `selectAll(_:)`.
nonisolated enum ListKey: String, CaseIterable, Sendable {
    case up
    case down
    case extendUp
    case extendDown
    /// Escape: several drop back to one.
    case drop
    /// Return: the conversation in its own window.
    case openWindow
    case delete

    var extends: Bool { self == .extendUp || self == .extendDown }

    private var input: String {
        switch self {
        case .up, .extendUp: UIKeyCommand.inputUpArrow
        case .down, .extendDown: UIKeyCommand.inputDownArrow
        case .drop: UIKeyCommand.inputEscape
        case .openWindow: "\r"
        case .delete: UIKeyCommand.inputDelete
        }
    }

    /// The key a command made by `command(action:)` stands for.
    @MainActor init?(_ command: UIKeyCommand) {
        guard let raw = command.propertyList as? String else { return nil }
        self.init(rawValue: raw)
    }

    /// A key command for the key, performing through `action`. It goes before the system's own use of the key, as
    /// moving the focus with the arrows.
    @MainActor func command(action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(
            title: "", action: action, input: input, modifierFlags: extends ? .shift : [], propertyList: rawValue)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
}
