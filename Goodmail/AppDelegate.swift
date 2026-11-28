import MailNotifications
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

    /// Windows the reader closed for good, which the system won't connect again. What was dropped for a message
    /// window that went away before it read its message back waited for it (`MinimizedDrafts.close`), and what
    /// arrived for a window that went away before it filled waited too (`ArrivalHold.windowGone`): both go now.
    func application(_ application: UIApplication, didDiscardSceneSessions sessions: Set<UISceneSession>) {
        for session in sessions {
            switch SessionRecord.of(session) {
            case .composing(let ticket): launch.running?.model.minimizedDrafts.discard(ticket)
            case .leftOpening: launch.routes.windowGone()
            case nil: break
            }
        }
    }

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploads.identifier else { return completionHandler() }
        // iOS can launch the app for this, so the database may still be opening. The task hands the handler on, or
        // calls it when the database couldn't open, so iOS owns it: it waits for the handler, and nothing else
        // awaits or cancels the task.
        Task { [launch] in
            guard let model = try? await launch.services().model else { return completionHandler() }
            model.handleBackgroundUploadEvents { @MainActor in completionHandler() }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Push registers only once the database has opened.
        launch.running?.push.didRegister(deviceToken: deviceToken)
    }

    /// The relay's quiet push, sent when mail was read, filed or deleted elsewhere (PushWorker/README.md). iOS can
    /// launch the app for it, so the database may still be opening.
    func application(
        _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // iOS hands over alerts that arrive while the app is open too: the extension and the sweep cover those.
        guard userInfo["handled"] != nil, let target = NewMailFetch.target(in: userInfo) else {
            return completionHandler(.noData)
        }
        // The task calls the handler on every path, so iOS owns it: it waits for the handler, and nothing else awaits
        // or cancels the task.
        Task { [launch] in
            guard let model = try? await launch.services().model else { return completionHandler(.failed) }
            let synced = await BackgroundDatabaseWork.shared.run("Mail dealt with elsewhere") {
                await model.syncHandledElsewhere(target)
            }
            completionHandler(synced ? .newData : .failed)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Logger.push.error("Couldn't register for push: \(error, privacy: .private)")
    }
}

extension AppDelegate {
    /// The menu bar. Its commands perform on the window with the keyboard focus (`ShakeToUndoWindow`).
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        MailMenus.build(builder, action: #selector(ShakeToUndoWindow.performCommand(_:)))
    }
}
