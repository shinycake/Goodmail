import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Shared by every window. Failing to open the database leaves nothing useful to show.
    let model: AppModel = {
        do {
            #if DEBUG
                if let count = SyntheticMailbox.requestedCount {
                    return try SyntheticMailbox.makeModel(threadCount: count)
                }
            #endif
            return try AppModel.openShared()
        } catch {
            fatalError("Couldn't open the mail database: \(error)")
        }
    }()
    private lazy var syncScheduler = SyncScheduler(model: model)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        syncScheduler.start()
        #if DEBUG
            TestDelivery.scheduleIfRequested(model: model)
        #endif
        return true
    }
}
