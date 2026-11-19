import MailCore
import UIKit
import WebKit

/// A web view set up for message bodies, with the handlers its configuration holds.
///
/// Made with a blank body loaded, so its content process is already running when a message takes it: starting one
/// takes from a few hundred milliseconds to seconds, which a reader opening a message would otherwise wait out.
final class PreparedWebView {
    let webView: WKWebView
    let cidHandler = CIDSchemeHandler()
    let messageHandler = MessageHandler()
    /// Where our script runs, apart from the page.
    static let world = WKContentWorld.world(name: "goodmail")

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = MessageWebViewPool.dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = [.link, .phoneNumber, .address, .calendarEvent]
        configuration.setURLSchemeHandler(cidHandler, forURLScheme: "cid")
        let label = String(
            localized: "Show Quoted Text", table: "Thread", bundle: .module, comment: "Accessibility label of the fold")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MessageScript.source(for: .reader(foldLabel: label)), injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: Self.world))
        configuration.userContentController.add(
            messageHandler, contentWorld: Self.world, name: MessageScript.handlerName)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(Self.blank, baseURL: nil)
    }

    /// The document a spare loads to start its content process, its script and our stylesheet.
    private static let blank = MessageDocument.html(
        for: MessageBody(plain: ""), palette: .adaptive, allowsRemoteContent: false)
}

/// Message web views made ahead of the reader, so a message that opens finds one already running.
public final class MessageWebViewPool {
    public static let shared = MessageWebViewPool()
    /// The reader opens one card at a time, and a second spare covers the next message or thread.
    static let spareCount = 2
    /// How long a spare waits to be made, so making it never holds up the frames of a thread that is opening.
    static let pause = Duration.milliseconds(400)
    /// One ephemeral store for every body, so the remote images a reader allowed stay cached for the session. Nothing a
    /// body loads outlives the app, and it keeps no cookies: one set by an image in one message must not follow the
    /// reader into the next.
    static let dataStore: WKWebsiteDataStore = {
        let store = WKWebsiteDataStore.nonPersistent()
        store.httpCookieStore.setCookiePolicy(.disallow)
        return store
    }()

    private var spares: [PreparedWebView] = []
    /// How many spares are ready now.
    var ready: Int { spares.count }
    /// Makes the missing spares one at a time. Owned here and never cancelled: the pool lives as long as the app, and
    /// making a spare can't fail.
    private var filling: Task<Void, Never>?

    init() {}

    /// Makes the spares and compiles the remote-content blocker while the app is idle, before any message opens.
    public func warmUp() {
        fill()
        RemoteContentBlocker.shared.prepare()
    }

    /// Returns once the missing spares are made.
    func filled() async {
        await filling?.value
    }

    /// A spare, or a new web view when none is ready yet; another spare is made in its place.
    func take() -> PreparedWebView {
        defer { fill() }
        return spares.isEmpty ? PreparedWebView() : spares.removeFirst()
    }

    private func fill() {
        guard filling == nil else { return }
        filling = Task {
            while spares.count < Self.spareCount, (try? await Task.sleep(for: Self.pause)) != nil {
                spares.append(PreparedWebView())
            }
            filling = nil
        }
    }
}

/// Forwards script messages without the user content controller retaining the view.
final class MessageHandler: NSObject, WKScriptMessageHandler {
    var onMessage: ((Any) -> Void)?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage?(message.body)
    }
}
