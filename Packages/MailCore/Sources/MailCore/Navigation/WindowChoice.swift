/// One open window, as an arrival from outside sees it when it picks where to go (`WindowChoice`).
public struct WindowFacts: Equatable, Sendable {
    /// What the window holds.
    public enum Holds: Equatable, Sendable {
        /// The mail screens, reading `thread` or nothing.
        case viewer(reading: ThreadSummary.ID?)
        /// One conversation alone, as in a window of its own on the Mac, which goes nowhere else.
        case message
        /// Something other than mail: a message being written, or Settings, in a window of its own.
        case otherWork
        /// The welcome screen or the other devices' accounts, as before the device has an account.
        case noMail
        /// Nothing yet: the database is still opening, or the window hasn't filled.
        case opening
    }

    public var holds: Holds
    /// Whether the window has the keyboard focus.
    public var isKey: Bool

    public init(_ holds: Holds, isKey: Bool = false) {
        self.holds = holds
        self.isKey = isKey
    }
}

/// Which window an arrival from outside goes to: a viewer already reading its conversation, else the key viewer, else
/// any viewer; with none, a new viewer window, or the one about to come up.
public enum WindowChoice: Equatable, Sendable {
    /// The window at this index of those given.
    case window(Int)
    /// A new viewer window, which takes the arrival as it comes up.
    case newViewer
    /// The first window to come up takes it.
    case wait
    /// There is nothing to show it in, as on the welcome screen.
    case nowhere

    /// What becomes of an arrival when no window is open.
    public enum NoWindow: Equatable, Sendable {
        /// The system brings a window up by itself, as at launch, or on iPhone and iPad.
        case comesUp
        /// None comes up unless the app opens one, as on the Mac once every window is closed.
        case staysClosed
    }

    /// Picks the window for an arrival that opens `thread`, or none, among `windows`, front first.
    public static func pick(reading thread: ThreadSummary.ID?, among windows: [WindowFacts], noWindow: NoWindow)
        -> WindowChoice
    {
        let viewers = windows.indices.filter { windows[$0].isViewer }
        if let thread, let reading = viewers.first(where: { windows[$0].holds == .viewer(reading: thread) }) {
            return .window(reading)
        }
        if let viewer = viewers.first(where: { windows[$0].isKey }) ?? viewers.first { return .window(viewer) }
        if windows.contains(where: { $0.holds == .opening }) { return .wait }
        if windows.contains(where: { $0.holds == .noMail }) { return .nowhere }
        if windows.isEmpty, noWindow == .comesUp { return .wait }
        return .newViewer
    }
}

extension WindowFacts {
    fileprivate var isViewer: Bool {
        guard case .viewer = holds else { return false }
        return true
    }
}
