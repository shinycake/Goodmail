import MailCore
import UIKit

/// The app's open mail windows, for what reaches past one window: an intent's route, the Undo Send toast of a message
/// written in a window of its own, the Settings window's changes.
enum MailWindows {
    /// The mail windows' coordinators, front first: the one with the keyboard focus, as several windows can be in
    /// front side by side on iPad, then any in front, then any at all. A window can come up more than once.
    static var frontFirst: [SceneCoordinator] {
        let scenes = Array(UIApplication.shared.connectedScenes)
        return (scenes.filter(isKey) + scenes.filter(isInFront) + scenes).compactMap {
            ($0.delegate as? SceneDelegate)?.coordinator
        }
    }

    /// Every window, once each and front first as `frontFirst` orders them, as an arrival from outside sees it, with
    /// its coordinator while it shows mail.
    static var facing: [(facts: WindowFacts, coordinator: SceneCoordinator?)] {
        let scenes = Array(UIApplication.shared.connectedScenes)
        var seen: Set<ObjectIdentifier> = []
        return (scenes.filter(isKey) + scenes.filter(isInFront) + scenes).compactMap { scene in
            guard let delegate = scene.delegate as? SceneDelegate, seen.insert(ObjectIdentifier(scene)).inserted
            else { return nil }
            return (WindowFacts(delegate.holds, isKey: isKey(scene)), delegate.coordinator)
        }
    }

    private static func isKey(_ scene: UIScene) -> Bool {
        (scene as? UIWindowScene)?.keyWindow?.isKeyWindow == true
    }

    private static func isInFront(_ scene: UIScene) -> Bool {
        scene.activationState == .foregroundActive
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
