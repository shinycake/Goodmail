import MailCore
import MailUI
import OSLog
import UIKit

/// Hands arrivals from outside to a window and holds the newest while none can take it (`ArrivalHold`): one already
/// reading the conversation, else the key viewer, else any viewer, which comes forward; with none, a new viewer window
/// on the Mac, or the first viewer to come up.
final class IntentRoutes {
    private var hold = ArrivalHold()

    func open(_ route: Route) {
        arrive(.route(route))
    }

    /// Hands `arrival` to the window it belongs in, or holds it for one to come up.
    func arrive(_ arrival: Arrival) {
        let windows = MailWindows.facing
        deliver(hold.arrive(arrival, among: windows.map(\.facts), onMac: Self.onMac, now: .now), among: windows)
    }

    /// Holds `arrival`, which the system gave a window that is still coming up.
    func hold(_ arrival: Arrival) {
        hold.hold(arrival)
    }

    /// A window filled, holding `holds`. Returns what it takes itself, as a viewer takes what was held; what any
    /// other window was given goes to the window it belongs in, so a message, compose or Settings window drops nothing.
    @discardableResult
    func filled(_ holds: WindowFacts.Holds) -> Arrival? {
        let windows = MailWindows.facing
        let delivery = hold.filled(holds, among: windows.map(\.facts), onMac: Self.onMac, now: .now)
        if case .takeHere(let arrival) = delivery { return arrival }
        deliver(delivery, among: windows)
        return nil
    }

    /// The thread open in the frontmost window, or `nil` when none is.
    var openThread: ThreadSummary.ID? { MailWindows.frontFirst.first?.openThread }

    private func deliver(_ delivery: ArrivalHold.Delivery, among windows: [MailWindows.Facing]) {
        switch delivery {
        case .none, .takeHere:
            break
        case .give(let arrival, let index):
            let chosen = windows[index]
            chosen.coordinator?.arrive(arrival)
            if !chosen.facts.isKey || chosen.scene.activationState != .foregroundActive {
                Self.bringForward(chosen.scene)
            }
        case .openViewer:
            SceneCoordinator.openWindow(for: WindowState().activity, beside: nil) { [weak self] in
                Logger(subsystem: "com.idanbirman.goodmail", category: "windows")
                    .error("Couldn't open a viewer window for an arrival")
                self?.hold.newViewerFailed()
            }
        }
    }

    /// Brings the window `scene` shows to the front, so what arrived shows where the reader looks.
    private static func bringForward(_ scene: UIScene) {
        // Nothing to do when the system won't: the window has what arrived when the reader comes to it.
        UIApplication.shared.activateSceneSession(
            for: UISceneSessionActivationRequest(session: scene.session), errorHandler: nil)
    }

    /// Whether windows stay closed once the reader has closed them all, as on the Mac.
    private static var onMac: Bool {
        ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac
    }
}
