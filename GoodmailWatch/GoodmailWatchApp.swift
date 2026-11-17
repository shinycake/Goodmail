import Foundation
import MailCore
import MailWrist
import MailWristUI
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
            if phase == .active { delegate.own.checkMail() }
        }
    }
}

/// Owns the link to the iPhone and the watch's own mail for the app's lifetime, from launch: the system can launch the app without a window
/// to hand it what the iPhone sent.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let inbox = WristInboxModel()
    let threads = WristThreads()
    let route = WristRoute()
    /// The Gmail and Outlook accounts the watch reads itself (ADR-023).
    let own = OwnMail()
    private let channel = WristChannel()
    /// Shows each snapshot the iPhone sends, stores and sends each change, and asks for each conversation opened.
    /// Ends with the app; nothing cancels it.
    private var following: Task<Void, Never>?

    func applicationDidFinishLaunching() {
        // Before launch finishes, so that the tap on an alert that launched the app reaches it.
        UNUserNotificationCenter.current().delegate = self
        // In the App Group, where the watch face's widget extension reads it.
        let store = WristStore(directory: SharedContainer.directoryURL ?? .applicationSupportDirectory)
        #if DEBUG
            // `-GoodmailWristSample en` (or `he`) shows made-up mail without an iPhone, for screenshots;
            // `-GoodmailWristSampleOpen YES` opens its first conversation.
            if let language = UserDefaults.standard.string(forKey: "GoodmailWristSample")
                .flatMap(WristSnapshot.SampleLanguage.init)
            {
                let sample = WristSnapshot.sample(language)
                inbox.receive(.snapshot(sample))
                for thread in WristThread.samples(for: sample, language) { threads.receive(.thread(thread)) }
                if UserDefaults.standard.bool(forKey: "GoodmailWristSampleOpen"), let first = sample.rows.first {
                    route.open(first.id)
                }
                following = Task { [inbox, threads, own] in
                    // Stored for the watch face; failing leaves the face on the last mailbox, fine for screenshots.
                    try? await store.save(inbox.mailbox)
                    WidgetCenter.shared.reloadAllTimelines()
                    // With `-GoodmailWristIndependent YES`, the watch also reads the sample's Gmail account itself.
                    if OwnMail.forcesIndependence { await own.run(inbox: inbox, threads: threads) }
                }
                return
            }
        #endif
        following = Task { [inbox, threads, channel, own] in
            async let link: Void = WristLink.run(
                inbox: inbox, threads: threads, store: store, channel: channel, runOwn: own.run,
                stored: { WidgetCenter.shared.reloadAllTimelines() })
            async let ownMail: Void = own.run(inbox: inbox, threads: threads)
            _ = await (link, ownMail)
        }
    }
}

/// A tap on a new-mail alert mirrored from the iPhone opens its conversation. watchOS calls this on its own queue,
/// so it reads the thread there and hops to the main actor to show it.
extension WatchAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let thread = AlertedThread.thread(in: response.notification.request.content.userInfo)
        else { return }
        await route.open(thread)
    }
}
