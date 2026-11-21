import MailCore
import OSLog
import UIKit

extension PresenceTracker {
    /// One per process, like the lifecycle it follows and the database suspension that follows it. A Mac runs the app
    /// as a Catalyst app, or as an iPad app, and keeps either running with no window open. There UIKit says nothing
    /// when the reader moves to another app and back, so AppKit's news drives presence too.
    static let shared: PresenceTracker = {
        let isMac = ProcessInfo.processInfo.isMacCatalystApp
        let uiKit = [
            PresenceSource(UIApplication.didBecomeActiveNotification, .becameActive),
            PresenceSource(UIApplication.willResignActiveNotification, .resignedActive),
            PresenceSource(UIApplication.didEnterBackgroundNotification, .enteredBackground),
            PresenceSource(UIApplication.willEnterForegroundNotification, .enteringForeground),
        ]
        let tracker = PresenceTracker(
            launchedIn: AppLaunchState(UIApplication.shared.applicationState),
            policy: isMac ? .keepsRunning : .suspends,
            sources: uiKit + (isMac ? PresenceSource.appKit : []))
        let log = Logger(subsystem: "com.idanbirman.goodmail", category: "presence")
        log.notice(
            "Policy \(String(describing: tracker.policy), privacy: .public), launched as \(String(describing: tracker.presence), privacy: .public)"
        )
        tracker.follow { old, new in
            log.notice("\(String(describing: old), privacy: .public) to \(String(describing: new), privacy: .public)")
        }
        return tracker
    }()
}

extension AppLaunchState {
    fileprivate init(_ state: UIApplication.State) {
        switch state {
        case .active: self = .active
        case .background: self = .background
        case .inactive: self = .inactive
        @unknown default: self = .inactive
        }
    }
}
