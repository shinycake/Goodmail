import UIKit

#if canImport(MailIntents)
    import MailIntents
#endif

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
    /// Where intents send the app's windows.
    let intentRoutes = IntentRoutes()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        syncScheduler.start()
        #if canImport(MailIntents)
            let host = IntentsHost(database: model.database, commands: model.commands, routes: intentRoutes)
            host.register()
            model.didChange = SpotlightIndexer(host: host).follow
        #endif
        #if DEBUG
            TestDelivery.scheduleIfRequested(model: model)
            SyntheticMailbox.deliverArrivalsIfRequested(to: model.database)
            TestMailTools.runIfRequested(model: model)
        #endif
        return true
    }

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploads.identifier else { return completionHandler() }
        model.handleBackgroundUploadEvents { @MainActor in completionHandler() }
    }
}
