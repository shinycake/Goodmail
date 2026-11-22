import MailCore
import MailUI
import UIKit

/// New Viewer Window with no window open at all, as Mail's opens one. A window answers it itself while it has the focus
/// (`EveryWindowCommands`), since it takes every menu command; one no window answers travels up the responder chain
/// past the scene and the application to here. Where the menu bar has the system's own New Window, as on iPad, the
/// command isn't in the menu bar, and iPhone opens no windows.
extension AppDelegate {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard action == #selector(ShakeToUndoWindow.performCommand(_:)) else {
            return super.canPerformAction(action, withSender: sender)
        }
        return (sender as? UICommand).flatMap(MailCommand.init) == .newWindow
            && UIApplication.shared.supportsMultipleScenes
    }

    @objc func performCommand(_ command: UICommand) {
        guard MailCommand(command) == .newWindow else { return }
        let front = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        SceneCoordinator.openWindow(for: WindowState().activity, beside: front) {}
    }
}
