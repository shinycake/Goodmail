import MailCore
import UIKit

/// A thread answers, moves and marks itself from the keyboard, as its toolbar does.
extension ThreadViewController: KeyboardShortcutScreen {
    public func action(for shortcut: KeyboardShortcut) -> (() -> Void)? {
        let model = viewModel
        switch shortcut {
        case .reply: return { model.answer(.reply) }
        case .replyAll: return { model.answer(.replyAll) }
        case .forward: return { model.answer(.forward) }
        case .archive: return { model.perform(.archive) }
        // In Trash, the toolbar offers Delete Forever, which asks first; the keyboard leaves that to the button.
        case .trash: return model.isInTrash ? nil : { model.perform(.trash) }
        case .markUnread: return { model.perform(.markRead(false)) }
        case .star: return { model.perform(.star(!model.isStarred)) }
        case .newMessage, .getMail, .search, .send: return nil
        }
    }
}
