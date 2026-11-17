import Foundation
import MailCore
import MailWrist
import MailWristUI
import SwiftUI
import WatchKit
import WidgetKit

/// Goodmail on Apple Watch (ADR-022): the Inbox the iPhone sends it.
@main
struct GoodmailWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if UserDefaults.standard.bool(forKey: "GoodmailWristSampleOpen") {
                    WristSampleThreadScreen(inbox: delegate.inbox, threads: delegate.threads)
                } else {
                    WristInboxView(model: delegate.inbox, threads: delegate.threads)
                }
            #else
                WristInboxView(model: delegate.inbox, threads: delegate.threads)
            #endif
        }
    }
}

/// Owns the link to the iPhone for the app's lifetime, from launch: the system can launch the app without a window
/// to hand it what the iPhone sent.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let inbox = WristInboxModel()
    let threads = WristThreads()
    private let channel = WristChannel()
    /// Shows each snapshot the iPhone sends, stores and sends each change, and asks for each conversation opened.
    /// Ends with the app; nothing cancels it.
    private var following: Task<Void, Never>?

    func applicationDidFinishLaunching() {
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
                following = Task { [inbox] in
                    // Stored for the watch face; failing leaves the face on the last mailbox, fine for screenshots.
                    try? await store.save(inbox.mailbox)
                    WidgetCenter.shared.reloadAllTimelines()
                }
                return
            }
        #endif
        following = Task { [inbox, threads, channel] in
            await WristLink.run(inbox: inbox, threads: threads, store: store, channel: channel) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
