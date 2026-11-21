public import Foundation

/// What reaches the app's windows from outside them: a route from an intent, a tapped alert, Spotlight or a widget; a
/// `mailto:` link or transfer code; a Home Screen quick action; or a window handed off from another device.
public enum Arrival: Equatable, Sendable {
    case route(Route)
    case link(URL)
    case quickAction(QuickAction)
    case handoff(WindowState)

    /// The conversation it opens, which a window already reading it takes first (`WindowChoice`).
    public var thread: ThreadSummary.ID? {
        guard case .route(.thread(let thread, _)) = self else { return nil }
        return thread
    }
}

/// Where the app's arrivals go (`WindowChoice`), and the one arrival it holds, the newest, while no window can take
/// it: for the first mail window to fill, as at launch or while the database opens, or for the viewer window it
/// opened for it. A message window never takes one: what was held is chosen for again once it fills.
public struct ArrivalHold: Equatable, Sendable {
    /// What is held, and for which window.
    enum Held: Equatable, Sendable {
        case nothing
        /// The first viewer to fill takes it.
        case forFirstWindow(Arrival)
        /// The viewer window opened for it at `asked`. Arrivals until it fills replace this one rather than open
        /// another, unless it is long overdue.
        case forNewViewer(Arrival, asked: Date)
    }

    /// What the app does with an arrival now.
    public enum Delivery: Equatable, Sendable {
        /// Nothing yet: it is held, or there is nowhere to show it.
        case none
        /// Gives it to the window at this index of those given.
        case give(Arrival, toWindow: Int)
        /// Opens a new viewer window, which takes it as it fills.
        case openViewer
        /// The window that just filled takes it.
        case takeHere(Arrival)
    }

    /// How long a viewer window asked for may take to fill before an arrival asks for another.
    public static let newViewerWait: TimeInterval = 10

    private(set) var held = Held.nothing
    /// Whether a mail window has filled since launch; after that, a Mac with every window closed has none coming up.
    private var mailWindowFilled = false

    public init() {}

    /// `arrival` came from outside, with `windows` open, front first. `onMac` says whether windows stay closed once
    /// the reader has closed them all.
    public mutating func arrive(_ arrival: Arrival, among windows: [WindowFacts], onMac: Bool, now: Date) -> Delivery {
        let noWindow: WindowChoice.NoWindow = onMac && mailWindowFilled ? .staysClosed : .comesUp
        switch WindowChoice.pick(reading: arrival.thread, among: windows, noWindow: noWindow) {
        case .window(let index):
            held = .nothing
            return .give(arrival, toWindow: index)
        case .nowhere:
            held = .nothing
            return .none
        case .wait:
            hold(arrival)
            return .none
        case .newViewer:
            if case .forNewViewer(_, let asked) = held, now.timeIntervalSince(asked) < Self.newViewerWait {
                held = .forNewViewer(arrival, asked: asked)
                return .none
            }
            held = .forNewViewer(arrival, asked: now)
            return .openViewer
        }
    }

    /// Holds `arrival`, which the system gave a window still coming up, in place of anything held before.
    public mutating func hold(_ arrival: Arrival) {
        switch held {
        case .forNewViewer(_, let asked): held = .forNewViewer(arrival, asked: asked)
        case .nothing, .forFirstWindow: held = .forFirstWindow(arrival)
        }
    }

    /// A window filled, holding `holds`, among `windows`, itself included. A viewer takes what is held. Any other
    /// window leaves it to be chosen for again, so a message window restored before a viewer doesn't take a
    /// conversation it can't show, nor drop it.
    public mutating func filled(_ holds: WindowFacts.Holds, among windows: [WindowFacts], onMac: Bool, now: Date)
        -> Delivery
    {
        switch holds {
        case .viewer, .message: mailWindowFilled = true
        case .otherWork, .noMail, .opening: break
        }
        let arrival: Arrival
        switch held {
        case .nothing: return .none
        case .forFirstWindow(let waiting), .forNewViewer(let waiting, _): arrival = waiting
        }
        if case .viewer = holds {
            held = .nothing
            return .takeHere(arrival)
        }
        return arrive(arrival, among: windows, onMac: onMac, now: now)
    }

    /// The viewer window opened for what is held couldn't open: it is dropped.
    public mutating func newViewerFailed() {
        if case .forNewViewer = held { held = .nothing }
    }
}
