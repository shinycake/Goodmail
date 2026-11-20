import MailCore
import OSLog
import UIKit

/// Whether anyone is looking at the app, and whether the system may stop it (ADR-033). The only observer of UIKit's
/// lifecycle notifications in the app target and the only code that changes `presence`. Sync, the change watches, the
/// database and push follow it through `follow(_:)` and never read the lifecycle themselves.
///
/// One per process, like the lifecycle it follows and the database suspension that follows it.
final class PresenceTracker {
    static let shared = PresenceTracker()

    /// What this platform does when the reader looks away. A Mac runs the app as a Catalyst app, or as an iPad app,
    /// and keeps either running with no window open.
    let policy: PresencePolicy = ProcessInfo.processInfo.isMacCatalystApp ? .keepsRunning : .suspends
    private(set) var presence: AppPresence
    /// Told of each change, in the order they asked, for the life of the process.
    private var followers: [(_ old: AppPresence, _ new: AppPresence) -> Void] = []
    private let log = Logger(subsystem: "com.idanbirman.goodmail", category: "presence")

    private init() {
        presence = AppPresence(launchedIn: AppLaunchState(UIApplication.shared.applicationState), policy: policy)
        let events: [(Notification.Name, PresenceEvent)] = [
            (UIApplication.didBecomeActiveNotification, .becameActive),
            (UIApplication.willResignActiveNotification, .resignedActive),
            (UIApplication.didEnterBackgroundNotification, .enteredBackground),
            (UIApplication.willEnterForegroundNotification, .enteringForeground),
        ]
        for (name, event) in events {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // UIKit posts these on the main thread, and the queue delivers them there.
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
        log.notice(
            "Policy \(String(describing: self.policy), privacy: .public), launched as \(String(describing: self.presence), privacy: .public)"
        )
    }

    /// Calls `change` with the old and new presence each time it changes, for the life of the process. Read
    /// `presence` for where it is now.
    func follow(_ change: @escaping (_ old: AppPresence, _ new: AppPresence) -> Void) {
        followers.append(change)
    }

    /// The one place `presence` changes.
    private func handle(_ event: PresenceEvent) {
        let old = presence
        let new = old.after(event, policy: policy)
        guard new != old else {
            log.debug(
                "\(String(describing: event), privacy: .public) leaves \(String(describing: old), privacy: .public) as it is"
            )
            return
        }
        presence = new
        let change = "\(event): \(old) to \(new)"
        log.notice("\(change, privacy: .public)")
        for follower in followers { follower(old, new) }
    }
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
