#if DEBUG
    import Foundation
    import MailCore

    /// Launch with `-GoodmailTestArrivalThread synthetic-1/t19` to have the app open that conversation a few seconds
    /// later as a tapped new-mail alert does (`PushCoordinator`), so the UI tests can check what an alert does to a
    /// window already reading another. `-GoodmailTestArrivalAfter` sets the seconds, 8 unless given.
    enum TestArrival {
        static func scheduleIfRequested(routes: IntentRoutes) {
            let defaults = UserDefaults.standard
            guard let name = defaults.string(forKey: "GoodmailTestArrivalThread") else { return }
            let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return print("Test arrival needs account/thread, not \(name)") }
            let thread = ThreadSummary.ID(accountID: AccountID(rawValue: parts[0]), threadID: parts[1])
            let delay = defaults.integer(forKey: "GoodmailTestArrivalAfter")
            // A debug launch option: nothing awaits or cancels it, and it ends once it has opened the conversation.
            Task {
                try? await Task.sleep(for: .seconds(delay > 0 ? delay : 8))
                routes.open(.thread(thread, in: .inbox))
            }
        }
    }
#endif
