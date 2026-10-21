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
        coordinator = SceneCoordinator(window: window, model: model)
        coordinator?.start()
        window.makeKeyAndVisible()
        self.window = window
    }
}
