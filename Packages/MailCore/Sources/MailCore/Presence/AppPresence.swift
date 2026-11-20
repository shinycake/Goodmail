/// Whether anyone is looking at the app, and whether the system may stop it (ADR-033). The app's `PresenceTracker`
/// holds the one value and makes every change through `after(_:policy:)`. Sync, the change watches, the database and
/// push follow it, and none of them reads the app's lifecycle itself.
public enum AppPresence: Sendable, Equatable {
    /// A window has the reader's attention.
    case attended
    /// iOS: something passed over the app while the reader was using it, such as Control Center, a call or the app
    /// switcher. Everything that ran while attended goes on.
    case covered
    /// iOS: in the foreground but not active yet, at launch or on the way back from the background. The database is
    /// open; sync waits for the reader.
    case arriving
    /// Mac: running with no one looking, behind other apps or with no window open, and free to keep running.
    case unattended
    /// iOS: in the background, where the system may freeze the process at any moment. The database is suspended
    /// whenever no work holding a background task needs it, and sync waits for background app refresh.
    case suspendable

    /// Where a process starts, from the state the system launched it in.
    public init(launchedIn state: AppLaunchState, policy: PresencePolicy) {
        switch (state, policy) {
        case (.active, _): self = .attended
        case (.inactive, .suspends): self = .arriving
        case (.background, .suspends): self = .suspendable
        case (.inactive, .keepsRunning), (.background, .keepsRunning): self = .unattended
        }
    }

    /// Where `event` takes the app on a platform that follows `policy`. The only transition function.
    public func after(_ event: PresenceEvent, policy: PresencePolicy) -> AppPresence {
        switch (event, policy) {
        case (.becameActive, _): .attended
        case (.resignedActive, .suspends): self == .attended ? .covered : self
        case (.enteredBackground, .suspends): .suspendable
        case (.enteringForeground, .suspends): self == .suspendable ? .arriving : self
        case (.resignedActive, .keepsRunning), (.enteredBackground, .keepsRunning): .unattended
        case (.enteringForeground, .keepsRunning): self
        }
    }

    /// How long sync waits between rounds, or nil where it doesn't poll at all.
    public var syncInterval: Duration? {
        switch self {
        case .attended, .covered: .seconds(30)
        case .unattended: .seconds(5 * 60)
        case .arriving, .suspendable: nil
        }
    }

    /// Whether the reader is with the app, so the mail it syncs counts as seen.
    public var showsMail: Bool {
        switch self {
        case .attended, .covered: true
        case .arriving, .unattended, .suspendable: false
        }
    }
}

/// What a platform does when the reader looks away. Chosen once per process, at the app's edge.
public enum PresencePolicy: Sendable, Equatable {
    /// iOS and iPadOS: attended, then covered or arriving, then suspendable.
    case suspends
    /// macOS: attended or unattended, never suspendable, and nothing launches the app in the background.
    case keepsRunning
}

/// The system's lifecycle news, as the app's UIKit notifications bring it.
public enum PresenceEvent: Sendable, Equatable {
    case becameActive
    case resignedActive
    case enteredBackground
    case enteringForeground
}

/// The state the system launched the process in, as `UIApplication.State` gives it.
public enum AppLaunchState: Sendable, Equatable {
    case active
    case inactive
    case background
}
