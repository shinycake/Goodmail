import MailCore
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: SceneCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let model = (UIApplication.shared.delegate as! AppDelegate).model
        // A handoff from another device wins over what this window showed when it was last saved.
        let restoring = (connectionOptions.userActivities + [session.stateRestorationActivity].compactMap(\.self))
            .lazy.compactMap(Self.windowState(in:)).first
        coordinator = SceneCoordinator(window: window, model: model, restoring: restoring)
        coordinator?.start()
        window.makeKeyAndVisible()
        self.window = window
    }

    /// Saved with the scene when the system puts the window away, and handed back to `willConnectTo` with it.
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        coordinator?.activity
    }

    /// Handoff into a window that is already open.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let state = Self.windowState(in: userActivity) else { return }
        coordinator?.showHandedOff(state)
    }

    private static func windowState(in activity: NSUserActivity) -> WindowState? {
        guard activity.activityType == WindowState.activityType,
            let saved = activity.userInfo?[WindowState.activityKey] as? Data
        else { return nil }
        return try? WindowState(saved: saved)
    }
}
