public import MailCore

/// Where a window opens a new message.
nonisolated public enum ComposePlacement: Sendable, Equatable {
    /// A sheet over the window, which can be minimized into the drafts pill.
    case sheet
    /// A window of its own, as every new message, reply and forward has on the Mac. Closing it saves the message to
    /// Drafts, as closing the sheet does, and the drafts pill stays empty.
    case ownWindow
}

/// Where a window opens Settings.
nonisolated public enum SettingsPlacement: Sendable, Equatable {
    /// A cover over the mail screens, with a button to close it.
    case cover
    /// The one Settings window, brought forward when it is already open.
    case ownWindow
}

/// The windows a window opens differ by how it is driven, and only here (ADR-011, ADR-032): a `Route` still names
/// where to go, and the scene coordinator asks these how to present it.
extension InteractionStyle {
    public var composePlacement: ComposePlacement {
        switch self {
        case .touch: .sheet
        case .desktop: .ownWindow
        }
    }

    public var settingsPlacement: SettingsPlacement {
        switch self {
        case .touch: .cover
        case .desktop: .ownWindow
        }
    }

    /// How a window that opens one thread lays it out: the reader alone on a desktop, where Return or a double-click
    /// opens one to keep beside other work; the whole viewer on touch.
    public var threadWindowLayout: WindowState.Layout {
        switch self {
        case .touch: .viewer
        case .desktop: .message
        }
    }

    /// `state` as a window driven this way shows it. Only a desktop has message windows, so one handed off or restored
    /// from a Mac opens as the viewer on touch, with its thread open.
    public func laying(out state: WindowState) -> WindowState {
        switch self {
        case .touch: state.asViewer
        case .desktop: state
        }
    }
}
