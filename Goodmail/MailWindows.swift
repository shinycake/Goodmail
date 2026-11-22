import MailCore
import UIKit

/// The app's open mail windows, for what reaches past one window: an intent's route, the Undo Send toast of a message
/// written in a window of its own, the Settings window's changes.
enum MailWindows {
    /// The mail windows' coordinators, front first (`scenesFrontFirst`).
    static var frontFirst: [SceneCoordinator] {
        scenesFrontFirst.compactMap { ($0.delegate as? SceneDelegate)?.coordinator }
    }

    /// A window as an arrival from outside sees it: its scene, what it holds, and its coordinator while it shows mail.
    struct Facing {
        let scene: UIScene
        let facts: WindowFacts
        let coordinator: SceneCoordinator?
    }

    /// Every window, front first, as an arrival from outside sees it.
    static var facing: [Facing] {
        let scenes = scenesFrontFirst
        // Until a window has become key, each scene's own key window says.
        let front = focus.front(among: scenes.map(id(of:)))
        return scenes.compactMap { scene in
            guard let delegate = scene.delegate as? SceneDelegate else { return nil }
            let isKey = front.map { $0 == id(of: scene) } ?? hasKeyWindow(scene)
            return Facing(
                scene: scene, facts: WindowFacts(delegate.holds, isKey: isKey), coordinator: delegate.coordinator)
        }
    }

    /// The order the reader was last in the windows (`WindowFocus`). A window scene's own key window says only which
    /// of that scene's windows has the focus, so on the Mac every open window says it is key, in front or behind; its
    /// active appearance is what follows the focus there.
    private static var focus = WindowFocus<String>()

    /// The reader is in `window` now: it became key, or, on the Mac, came in front of the others. Each of the app's
    /// windows tells it so (`ShakeToUndoWindow`).
    static func cameToFront(_ window: UIWindow) {
        guard let scene = window.windowScene else { return }
        focus.focused(id(of: scene), open: UIApplication.shared.connectedScenes.map(id(of:)))
    }

    /// Every window once, front first: the ones the reader was in most recently first; then any whose scene has a key
    /// window, as the one with the keyboard focus among several side by side on iPad; then any in front; then any.
    private static var scenesFrontFirst: [UIScene] {
        let scenes = Array(UIApplication.shared.connectedScenes)
        var seen: Set<ObjectIdentifier> = []
        let byScene = (scenes.filter(hasKeyWindow) + scenes.filter(isInFront) + scenes).filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
        let order = focus.ordered(byScene.map(id(of:)))
        return order.compactMap { id in byScene.first { Self.id(of: $0) == id } }
    }

    private static func id(of scene: UIScene) -> String {
        scene.session.persistentIdentifier
    }

    private static func hasKeyWindow(_ scene: UIScene) -> Bool {
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
