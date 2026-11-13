#if DEBUG
    import Foundation
    import OSLog

    /// `-GoodmailRunBackgroundRefresh YES` runs background app refresh right after launch, on a background queue as
    /// iOS does, with a stand-in for the task. The launch tests use it to catch a refresh that needs the main actor,
    /// which traps there.
    nonisolated enum TestRefresh {
        static func runIfRequested(_ refresh: BackgroundRefresh) {
            guard UserDefaults.standard.bool(forKey: "GoodmailRunBackgroundRefresh") else { return }
            DispatchQueue.global(qos: .background).async { refresh.run(StandIn()) }
        }

        private final class StandIn: RefreshTask {
            var expirationHandler: (() -> Void)?

            func setTaskCompleted(success: Bool) {
                Logger(subsystem: "com.idanbirman.goodmail", category: "sync")
                    .notice("Test background refresh completed, success: \(success)")
            }
        }
    }
#endif
