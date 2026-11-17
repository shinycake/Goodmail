import Foundation
import MailWrist
import MailWristUI
import SwiftUI
import WatchKit

/// Goodmail on Apple Watch (ADR-022): the Inbox the iPhone sends it.
@main
struct GoodmailWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WristInboxView(model: delegate.inbox)
        }
    }
}

/// Owns the link to the iPhone for the app's lifetime, from launch: the system can launch the app without a window
/// to hand it what the iPhone sent.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let inbox = WristInboxModel()
    private let channel = WristChannel()
    /// Shows each snapshot the iPhone sends, and stores and sends each change. Ends with the app; nothing cancels it.
    private var following: Task<Void, Never>?

    func applicationDidFinishLaunching() {
        #if DEBUG
            // `-GoodmailWristSample en` (or `he`) shows made-up mail without an iPhone, for screenshots.
            if let language = UserDefaults.standard.string(forKey: "GoodmailWristSample")
                .flatMap(WristSnapshot.SampleLanguage.init)
            {
                inbox.receive(.snapshot(.sample(language)))
                return
            }
        #endif
        let store = WristStore(directory: URL.applicationSupportDirectory)
        following = Task { [inbox, channel] in await inbox.run(store: store, channel: channel) }
    }
}
