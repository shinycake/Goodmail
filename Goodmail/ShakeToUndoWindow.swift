import MailUI
import UIKit

/// A window that undoes the last mail action when shaken, from any screen, and offers the keyboard shortcuts of the
/// screens it shows.
///
/// A shake goes to the first responder and travels up the responder chain to the window, or straight to the window
/// when nothing is first responder, so catching it here needs no screen to hold first responder. A screen that did
/// would make UIKit reload the input views each time a menu opens, which raises the keyboard with no field focused.
/// A text field or view that is editing still takes the shake first, for its own Undo Typing.
final class ShakeToUndoWindow: UIWindow {
    private let undo: () -> Void

    init(windowScene: UIWindowScene, undo: @escaping () -> Void) {
        self.undo = undo
        super.init(windowScene: windowScene)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Key commands reach the window from any first responder, or straight away when there is none, for the same
    /// reason a shake does. Each screen says which shortcuts it answers now (`KeyboardShortcuts`).
    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? [])
            + KeyboardShortcuts.commands(in: rootViewController, action: #selector(performShortcut(_:)))
    }

    @objc private func performShortcut(_ command: UIKeyCommand) {
        KeyboardShortcuts.perform(command, in: rootViewController)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return super.motionEnded(motion, with: event) }
        undo()
    }
}
