import MailUI
import OSLog
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Shared by every window.
    let launch = AppLaunch()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        launch.start()
        return true
    }

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploads.identifier else { return completionHandler() }
        // iOS can launch the app for this, so the database may still be opening.
        Task { [launch] in
            guard let model = try? await launch.services().model else { return completionHandler() }
            model.handleBackgroundUploadEvents { @MainActor in completionHandler() }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Push registers only once the database has opened.
        launch.running?.push.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Logger.push.error("Couldn't register for push: \(error, privacy: .public)")
    }
}

extension AppDelegate {
    /// The menu bar. Its commands perform on the window with the keyboard focus (`ShakeToUndoWindow`).
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        MailMenus.build(builder, action: #selector(ShakeToUndoWindow.performShortcut(_:)))
    }
}
