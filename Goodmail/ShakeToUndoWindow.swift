import MailUI
import UIKit

/// A window that undoes the last mail action when shaken, from any screen, and performs the keyboard shortcuts and
/// menu bar commands of the screens it shows, and its own.
///
/// A shake goes to the first responder and travels up the responder chain to the window, or straight to the window
/// when nothing is first responder, so catching it here needs no screen to hold first responder. A screen that did
/// would make UIKit reload the input views each time a menu opens, which raises the keyboard with no field focused.
/// A text field or view that is editing still takes the shake first, for its own Undo Typing. Commands reach the window
/// the same way, so each window answers its own.
final class ShakeToUndoWindow: UIWindow {
    private let undo: () -> Void
    /// What the window itself does for a shortcut no screen answers, as New Window, or `nil` when it does nothing.
    var windowAction: (KeyboardShortcut) -> (() -> Void)? = { _ in nil }

    init(windowScene: UIWindowScene, undo: @escaping () -> Void) {
        self.undo = undo
        super.init(windowScene: windowScene)
        // The one place a window's interaction style is decided, at the app's edge: Mac windows are driven by pointer
        // and keyboard, all others by touch. Screens read it from their trait collection.
        traitOverrides.interactionStyle = InteractionStyle(idiom: windowScene.traitCollection.userInterfaceIdiom)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Without a menu bar, the window offers the shortcuts as key commands of its own, which reach it from any first
    /// responder, or straight away when there is none, for the same reason a shake does. Each screen says which
    /// shortcuts it answers now (`KeyboardShortcuts`).
    override var keyCommands: [UIKeyCommand]? {
        guard !MailMenus.inMenuBar else { return super.keyCommands }
        return (super.keyCommands ?? [])
            + KeyboardShortcuts.commands(in: rootViewController, action: #selector(performShortcut(_:)))
    }

    /// The menu bar's commands are enabled only while this window answers them.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(performShortcut(_:)):
            (sender as? UICommand).flatMap(KeyboardShortcut.init).flatMap(self.action(for:)) != nil
        case #selector(findAndReplace(_:)):
            MailMenus.inMenuBar && self.action(for: .search) != nil
        default:
            super.canPerformAction(action, withSender: sender)
        }
    }

    /// In the menu bar, Find & Replace holds ⌥⌘F, Apple Mail's Search Mail, so it searches the mail while no text has
    /// the keyboard. A text view that has it answers first, being ahead of the window in the responder chain.
    override func findAndReplace(_ sender: Any?) {
        action(for: .search)?()
    }

    @objc func performShortcut(_ command: UICommand) {
        KeyboardShortcut(command).flatMap(action(for:))?()
    }

    /// What `shortcut` does here: on the frontmost screen that answers it, else on the window.
    private func action(for shortcut: KeyboardShortcut) -> (() -> Void)? {
        KeyboardShortcuts.action(for: shortcut, in: rootViewController) ?? windowAction(shortcut)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return super.motionEnded(motion, with: event) }
        undo()
    }
}
