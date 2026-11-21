#if DEBUG
    import Foundation
    import MailCore

    /// Launch with `-GoodmailTestArrivalThread synthetic-1/t19` to have the app open that conversation as a tapped
    /// new-mail alert does (`PushCoordinator`) each time the UI test posts `TestTrigger.arrival`, once it has set the
    /// window up, so the tests can check what an alert does to a window already showing something.
    /// `-GoodmailTestArrivalAtLaunch YES` opens it as the database opens instead, before the window has filled, as an
    /// alert that launches the app does. A thread that isn't in the synthetic mailboxes arrives as one that is gone.
    enum TestArrival {
        static func scheduleIfRequested(routes: IntentRoutes) {
            let defaults = UserDefaults.standard
            guard let name = defaults.string(forKey: "GoodmailTestArrivalThread") else { return }
            guard let thread = ThreadSummary.ID(testName: name) else {
                return print("Test arrival needs account/thread, not \(name)")
            }
            guard !defaults.bool(forKey: "GoodmailTestArrivalAtLaunch") else {
                return routes.open(.thread(thread, in: .inbox))
            }
            TestTrigger.arrival.onPost { routes.open(.thread(thread, in: .inbox)) }
        }
    }

    extension ThreadSummary.ID {
        /// The thread a launch argument names as `account/thread`, as `synthetic-1/t19`.
        init?(testName name: String) {
            let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            self.init(accountID: AccountID(rawValue: parts[0]), threadID: parts[1])
        }
    }
#endif
