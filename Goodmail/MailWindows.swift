import UIKit

/// The app's open mail windows, for what reaches past one window: an intent's route, the Undo Send toast of a message
/// written in a window of its own, the Settings window's changes.
enum MailWindows {
    /// The mail windows' coordinators, front first: the one with the keyboard focus, as several windows can be in
    /// front side by side on iPad, then any in front, then any at all. A window can come up more than once.
    static var frontFirst: [SceneCoordinator] {
        let scenes = Array(UIApplication.shared.connectedScenes)
        let focused = scenes.filter { ($0 as? UIWindowScene)?.keyWindow?.isKeyWindow == true }
        let inFront = scenes.filter { $0.activationState == .foregroundActive }
        return (focused + inFront + scenes).compactMap { ($0.delegate as? SceneDelegate)?.coordinator }
    }

    /// Every mail window's coordinator, once each.
    static var all: [SceneCoordinator] {
        UIApplication.shared.connectedScenes.compactMap { ($0.delegate as? SceneDelegate)?.coordinator }
    }

    /// The front window showing the mail screens, with the mailboxes and the undo toast, rather than one
    /// conversation alone or the welcome screen.
    static var frontViewer: SceneCoordinator? {
        frontFirst.first { $0.split != nil }
    }
}
