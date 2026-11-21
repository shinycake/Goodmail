/// The one Settings window, where Settings has a window of its own: closed, asked of the system and not connected
/// yet, or open. Asking again while it is asked for opens no second window, and asking while it is open brings it
/// forward at the page asked for. `Window` names an open window, told apart by identity.
public enum SettingsWindowState<Window: AnyObject> {
    case closed
    /// Asked of the system, which hasn't connected the window yet. It opens at `page`, the last one asked for.
    case requested(SettingsPage)
    case open(Window)

    /// What a request for Settings does.
    public enum Request {
        /// Ask the system for the window.
        case open
        /// It is already asked for, and opens at the page just asked for.
        case wait
        /// Bring the open window forward, showing `page`.
        case raise(Window, at: SettingsPage)
    }

    /// What a Settings window that connects does.
    public enum Connection {
        /// Fill the window with Settings, open at `page`.
        case fill(at: SettingsPage)
        /// Another Settings window is open already: this one closes and that one comes forward.
        case duplicate(of: Window)
    }

    /// Settings was asked for, at `page`.
    public mutating func request(_ page: SettingsPage) -> Request {
        switch self {
        case .closed:
            self = .requested(page)
            return .open
        case .requested:
            self = .requested(page)
            return .wait
        case .open(let window):
            return .raise(window, at: page)
        }
    }

    /// The system wouldn't open the window it was asked for, so Settings can be asked for again.
    public mutating func requestFailed() {
        guard case .requested = self else { return }
        self = .closed
    }

    /// A Settings window connected: the one asked for, or one the system restored unasked, which opens at the first
    /// screen.
    public mutating func connected(_ window: Window) -> Connection {
        switch self {
        case .closed:
            self = .open(window)
            return .fill(at: .main)
        case .requested(let page):
            self = .open(window)
            return .fill(at: page)
        case .open(let open):
            return .duplicate(of: open)
        }
    }

    /// `window` closed. Settings is closed once the open window is.
    public mutating func closed(_ window: Window) {
        guard case .open(let open) = self, open === window else { return }
        self = .closed
    }
}

extension SettingsWindowState: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.closed, .closed): true
        case (.requested(let left), .requested(let right)): left == right
        case (.open(let left), .open(let right)): left === right
        case (.closed, _), (.requested, _), (.open, _): false
        }
    }
}

extension SettingsWindowState.Request: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.open, .open), (.wait, .wait): true
        case (.raise(let left, let leftPage), .raise(let right, let rightPage)): left === right && leftPage == rightPage
        case (.open, _), (.wait, _), (.raise, _): false
        }
    }
}

extension SettingsWindowState.Connection: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.fill(let left), .fill(let right)): left == right
        case (.duplicate(let left), .duplicate(let right)): left === right
        case (.fill, _), (.duplicate, _): false
        }
    }
}
