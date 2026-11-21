/// What the system says of the app's login item, as `SMAppService.Status` does. MailCore doesn't import
/// ServiceManagement, so the app maps the system's own value onto this one.
public enum LoginItemStatus: Sendable, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// Whether the Mac opens Goodmail when the reader logs in, as Settings shows it. The system owns the truth, so
/// every change ends by reading its status again (`init(_:)`) rather than assuming the call worked.
public enum OpenAtLogin: Sendable, Equatable {
    case off
    case on
    /// Registered, but the reader has to allow it in System Settings, Login Items.
    case needsApproval
    /// The system has no login item for this build, as an unsigned one.
    case unavailable
    /// The last change failed; the toggle reads as off until the status is read again.
    case failed(message: String)

    public init(_ status: LoginItemStatus) {
        switch status {
        case .notRegistered: self = .off
        case .enabled: self = .on
        case .requiresApproval: self = .needsApproval
        case .notFound: self = .unavailable
        }
    }

    /// What asking for a different setting has the system do.
    public enum Change: Sendable, Equatable {
        case register
        case unregister
    }

    /// Whether the toggle shows on. A login item waiting for approval is registered, so it shows on and the reader
    /// can turn it off again.
    public var isOn: Bool {
        switch self {
        case .on, .needsApproval: true
        case .off, .unavailable, .failed: false
        }
    }

    /// What to ask of the system to make the toggle `on`, or `nil` when it already is, or can't be changed.
    public func change(toggling on: Bool) -> Change? {
        switch self {
        case .unavailable: nil
        case .off, .on, .needsApproval, .failed:
            if on == isOn { nil } else { on ? .register : .unregister }
        }
    }
}
