public import Foundation

/// A lifecycle notification and the presence event it brings.
public struct PresenceSource: Sendable {
    public let name: Notification.Name
    public let event: PresenceEvent

    public init(_ name: Notification.Name, _ event: PresenceEvent) {
        self.name = name
        self.event = event
    }

    /// AppKit's activation news, which a Mac app gets by name. UIKit posts no resign or activate notification when
    /// the reader moves to another app and back on a Mac, so without these a Mac app would stay attended for the life
    /// of the process.
    public static let appKit = [
        PresenceSource(Notification.Name("NSApplicationDidBecomeActiveNotification"), .becameActive),
        PresenceSource(Notification.Name("NSApplicationDidResignActiveNotification"), .resignedActive),
    ]
}

/// Whether anyone is looking at the app, and whether the system may stop it (ADR-033). The only observer of the
/// lifecycle notifications in the app and the only code that changes `presence`. Sync, the change watches, the
/// database and push follow it through `follow(_:)` and never read the lifecycle themselves.
@MainActor
public final class PresenceTracker {
    /// What this platform does when the reader looks away.
    public let policy: PresencePolicy
    public private(set) var presence: AppPresence
    /// Told of each change, in the order they asked, for the life of the tracker.
    private var followers: [(_ old: AppPresence, _ new: AppPresence) -> Void] = []
    private let center: NotificationCenter
    private var observers: [any NSObjectProtocol] = []

    /// Follows `sources` on `center`. They must be posted on the main thread, as UIKit and AppKit post theirs.
    public init(
        launchedIn state: AppLaunchState, policy: PresencePolicy, sources: [PresenceSource],
        center: NotificationCenter = .default
    ) {
        self.policy = policy
        self.center = center
        presence = AppPresence(launchedIn: state, policy: policy)
        observers = sources.map { source in
            // No queue, so the block runs on the posting thread, which the sources' posters keep to the main one.
            center.addObserver(forName: source.name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(source.event) }
            }
        }
    }

    isolated deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    /// Calls `change` with the old and new presence each time it changes, for the life of the tracker. Read
    /// `presence` for where it is now.
    public func follow(_ change: @escaping (_ old: AppPresence, _ new: AppPresence) -> Void) {
        followers.append(change)
    }

    /// The one place `presence` changes.
    private func handle(_ event: PresenceEvent) {
        let old = presence
        let new = old.after(event, policy: policy)
        guard new != old else { return }
        presence = new
        for follower in followers { follower(old, new) }
    }
}

extension PresencePolicy {
    /// How often push subscriptions are brought up to date on a timer, or nil where coming back to the app and
    /// background refresh do it. A Mac app can run for days without the reader coming back to it, while Outlook's
    /// subscriptions last under three, so it renews well inside that. Bringing them up to date is cheap when nothing
    /// is due.
    public var pushRenewalInterval: Duration? {
        switch self {
        case .keepsRunning: .seconds(6 * 60 * 60)
        case .suspends: nil
        }
    }
}
