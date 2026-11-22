import Foundation
import MailCore

/// Edit > Undo and ⌘Z: the window's undo manager holds the one undo the actions keep, under its name, as "Undo
/// Archive", so the menu bar takes it back as a shake or the toast's Undo does. Text being edited keeps its own undos
/// in the same manager, in the order they were made.
extension MailActions {
    /// Puts the last undo in the undo manager in place of the one before, or takes it out once it is used. Only the
    /// last action can be undone, so the manager holds one at most.
    func offerUndo() {
        guard let undoManager else { return }
        undoManager.removeAllActions(withTarget: self)
        guard let lastUndo else { return }
        // A group of its own, as the manager wants one open to register in and a window groups only by event.
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { $0.undoLast() }
        undoManager.setActionName(lastUndo.name)
        undoManager.endUndoGrouping()
    }
}

extension MailActions.Undo {
    /// What the menu bar calls it after Undo; empty, for Undo alone, for a change the window isn't told of, as a pin.
    var name: String {
        switch self {
        case .actions(_, let change): change?.request.name ?? ""
        case .send:
            String(localized: "Send", table: "Compose", bundle: .module, comment: "Sends the message")
        }
    }
}

extension MailChange.Request {
    fileprivate var name: String {
        switch self {
        case .action(let action): action.title
        case .move:
            String(localized: "Move", table: "Actions", bundle: .module, comment: "Edit > Undo after moving threads")
        case .snooze:
            String(localized: "Snooze", table: "Actions", bundle: .module, comment: "Hides threads until a later time")
        case .unsnooze:
            String(localized: "Move to Inbox", table: "Actions", bundle: .module, comment: "Action: back to the Inbox")
        case .block:
            String(
                localized: "Block Sender", table: "SenderRules", bundle: .module,
                comment: "Menu command that writes a rule sending the sender's mail to Trash")
        }
    }
}
