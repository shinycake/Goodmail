import UIKit

/// The composer sends from the keyboard once the message can go, as its Send button does.
extension ComposeViewController: KeyboardShortcutScreen {
    public func action(for shortcut: KeyboardShortcut) -> (() -> Void)? {
        guard shortcut == .send, viewModel.canSend else { return nil }
        return { [weak self] in self?.send() }
    }
}
