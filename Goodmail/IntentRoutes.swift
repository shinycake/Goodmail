import MailCore
import MailUI
import OSLog
import UIKit

/// What reaches the app's windows from outside them: a route from an intent, a tapped alert, Spotlight or a widget; a
/// `mailto:` link or transfer code; a Home Screen quick action; or a window handed off from another device.
enum Arrival {
    case route(Route)
    case link(URL)
    case quickAction(QuickAction)
    case handoff(WindowState)

    /// The conversation it opens, which a window already reading it takes first (`WindowChoice`).
    var thread: ThreadSummary.ID? {
        guard case .route(.thread(let thread, _)) = self else { return nil }
        return thread
    }
}

/// Hands arrivals from outside to a window (`WindowChoice`): one already reading the conversation, else the key
/// viewer, else any viewer; with none, a new viewer window on the Mac, or the first window to come up. It holds one
/// arrival at a time for a window to come up, the newest, which that window applies before it is first built.
final class IntentRoutes {
    /// An arrival held for a window to come up, and which window that is.
    private enum Held {
        case nothing
        /// The first mail window to fill takes it, as at launch, or once the database has opened.
        case forFirstWindow(Arrival)
        /// The viewer window opened for it. Arrivals until it fills replace this one rather than open another.
        case forNewViewer(Arrival)
    }

    private var held = Held.nothing
    /// Whether a mail window has filled since launch, after which a Mac with every window closed has none coming up.
    private var windowFilled = false

    func open(_ route: Route) {
        arrive(.route(route))
    }

    /// Hands `arrival` to the window it belongs in, or holds it for one to come up.
    func arrive(_ arrival: Arrival) {
        if case .forNewViewer = held {
            held = .forNewViewer(arrival)
            return
        }
        let windows = MailWindows.facing
        switch WindowChoice.pick(reading: arrival.thread, among: windows.map(\.facts), noWindow: noWindow) {
        case .window(let index):
            held = .nothing
            windows[index].coordinator?.arrive(arrival)
        case .wait:
            held = .forFirstWindow(arrival)
        case .nowhere:
            held = .nothing
        case .newViewer:
            held = .forNewViewer(arrival)
            SceneCoordinator.openWindow(for: WindowState().activity, beside: nil) { [weak self] in
                Logger(subsystem: "com.idanbirman.goodmail", category: "windows")
                    .error("Couldn't open a viewer window for an arrival")
                self?.held = .nothing
            }
        }
    }

    /// Holds `arrival`, which the system gave a window that is still coming up, for the first to fill.
    func hold(_ arrival: Arrival) {
        switch held {
        case .forNewViewer: held = .forNewViewer(arrival)
        case .nothing, .forFirstWindow: held = .forFirstWindow(arrival)
        }
    }

    /// The arrival held for the mail window that is filling, which takes it.
    func takeArrival() -> Arrival? {
        windowFilled = true
        defer { held = .nothing }
        switch held {
        case .nothing: return nil
        case .forFirstWindow(let arrival), .forNewViewer(let arrival): return arrival
        }
    }

    /// The thread open in the frontmost window, or `nil` when none is.
    var openThread: ThreadSummary.ID? { MailWindows.frontFirst.first?.openThread }

    /// What becomes of an arrival with no window open: the Mac, once running, has none come up by itself.
    private var noWindow: WindowChoice.NoWindow {
        let mac = ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac
        return mac && windowFilled ? .staysClosed : .comesUp
    }
}
