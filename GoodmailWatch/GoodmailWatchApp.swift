import Foundation
import MailCore
import MailWrist
import MailWristUI
import OSLog
import SwiftUI
import UserNotifications
import WatchKit
import WidgetKit

/// Goodmail on Apple Watch (ADR-022, ADR-023): the Inbox the iPhone sends it, with the Gmail and Outlook accounts the
/// watch reads itself.
@main
struct GoodmailWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WristInboxView(model: delegate.inbox, threads: delegate.threads, route: delegate.route)
                // A tap on the watch face.
                .onOpenURL { delegate.route.open($0) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: delegate.own.ask(.check)
            case .background:
                delegate.own.ask(.prune)
                OwnMail.scheduleRefresh(after: .now)
            default: break
            }
        }
        .backgroundTask(.appRefresh(OwnMail.refreshIdentifier)) {
            await delegate.refreshOwnMail()
        }
    }
}

/// Owns the link to the iPhone and the watch's own mail for the app's lifetime, from launch: the system can launch the app without a window
/// to hand it what the iPhone sent.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let inbox: WristInboxModel
    let threads = WristThreads()
    let route = WristRoute()
    /// The Gmail and Outlook accounts the watch reads itself (ADR-023).
    let own: OwnMail
    private let channel = WristChannel()
    /// The alerts the relay sends the watch itself (ADR-023).
    let alerts: OwnAlerts
    /// In the App Group, where the watch face's widget extension reads it.
    let store: WristStore
    /// Shows each snapshot the iPhone sends, stores and sends each change, and asks for each conversation opened.
    /// Ends with the app; nothing cancels it.
    private var following: Task<Void, Never>?

    override init() {
        let inbox = WristInboxModel()
        let store = WristStore(directory: SharedContainer.directoryURL ?? .applicationSupportDirectory)
        self.inbox = inbox
        self.store = store
        own = OwnMail(inbox: inbox, store: store)
        alerts = OwnAlerts(channel: channel)
        super.init()
    }

    func applicationDidFinishLaunching() {
        // Before launch finishes, so that the tap on an alert that launched the app reaches it.
        UNUserNotificationCenter.current().delegate = self
        OwnAlerts.registerActions()
        #if DEBUG
            if WatchSample.showIfRequested(inbox: inbox, threads: threads, route: route) {
                following = Task { [inbox, threads, own, store, alerts] in
                    // Stored for the watch face; failing leaves the face on the last mailbox, fine for screenshots.
                    do {
                        try await store.save(inbox.mailbox)
                    } catch {
                        Logger(subsystem: "com.idanbirman.goodmail", category: "watch")
                            .error("Couldn't store the sample mailbox for the face: \(error, privacy: .private)")
                    }
                    WidgetCenter.shared.reloadAllTimelines()
                    // Alerts pushed with `simctl push` show and open over the sample.
                    async let alerting: Void = alerts.run()
                    // With `-GoodmailWristIndependent YES`, the watch also reads the sample's Gmail account itself.
                    if OwnMail.forcesIndependence { await own.run(inbox: inbox, threads: threads) }
                    await alerting
                }
                return
            }
        #endif
        following = Task { [inbox, threads, channel, own, store, alerts] in
            async let link: Void = WristLink.run(
                inbox: inbox, threads: threads, store: store, channel: channel, runOwn: own.run,
                ready: alerts.linkReady, stored: { WidgetCenter.shared.reloadAllTimelines() })
            async let ownMail: Void = own.run(inbox: inbox, threads: threads)
            async let alerting: Void = alerts.run()
            async let takingDown: Void = OwnAlerts.takeDownHandled(following: inbox)
            _ = await (link, ownMail, alerting, takingDown)
        }
    }
}

extension WatchAppDelegate {
    /// A background refresh of the mail the watch reads itself.
    func refreshOwnMail() async {
        await own.refresh(inbox: await restoredInbox(), threads: threads, store: store)
    }

    /// The Inbox, restored from the store first: the system can launch the app for an alert or a refresh, which then
    /// runs before the link to the iPhone has restored it.
    func restoredInbox() async -> WristInboxModel {
        if !inbox.isRestored { inbox.restore(await store.load()) }
        return inbox
    }
}
