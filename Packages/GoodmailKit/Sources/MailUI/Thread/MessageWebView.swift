import MailCore
import UIKit
import WebKit

/// One message's body (ADR-003): no email JavaScript, no remote loads until the reader allows them, `cid:` images
/// served from the message's own parts, and our script for direction, quote folding and sizing.
final class MessageWebView: UIView {
    struct Content: Equatable {
        var message: Message
        var allowsRemoteContent: Bool
    }

    /// Reports the body's height, and whether it holds remote content that is being blocked.
    var onLayout: ((_ height: CGFloat, _ hasBlockedRemoteContent: Bool) -> Void)?
    var openURL: ((URL) -> Void)?

    private let webView: WKWebView
    private let messageHandler = MessageHandler()
    private let cidHandler: CIDSchemeHandler
    private var heightConstraint: NSLayoutConstraint!
    private var content: Content?
    private static let world = WKContentWorld.world(name: "goodmail")

    /// `attachmentData` fetches a part a `cid:` URL names.
    init(attachmentData: @escaping (Attachment, Message.ID) async throws -> Data) {
        cidHandler = CIDSchemeHandler(attachmentData: attachmentData)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = [.link, .phoneNumber, .address, .calendarEvent]
        configuration.setURLSchemeHandler(cidHandler, forURLScheme: "cid")
        let label = String(localized: "Show Quoted Text", bundle: .module, comment: "Accessibility label of the fold")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MessageScript.source(foldLabel: label), injectionTime: .atDocumentEnd, forMainFrameOnly: true,
                in: Self.world))
        configuration.userContentController.add(
            messageHandler, contentWorld: Self.world, name: MessageScript.handlerName)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        heightConstraint = webView.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint,
        ])
        messageHandler.onMessage = { [weak self] body in self?.handle(body) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func show(_ content: Content) {
        guard content != self.content else { return }
        self.content = content
        cidHandler.message = content.message
        Task {
            let rules = webView.configuration.userContentController
            rules.removeAllContentRuleLists()
            if !content.allowsRemoteContent, let blocker = try? await RemoteContentBlocker.shared.ruleList() {
                rules.add(blocker)
            }
            webView.loadHTMLString(MessageDocument.html(for: content.message.body), baseURL: nil)
        }
    }

    private func handle(_ body: Any) {
        guard let body = body as? [String: Any], let height = body["height"] as? Double else { return }
        heightConstraint.constant = max(1, height)
        let hasRemote = body["hasRemote"] as? Bool ?? false
        onLayout?(heightConstraint.constant, hasRemote && content?.allowsRemoteContent == false)
    }
}

extension MessageWebView: WKNavigationDelegate {
    /// The body loads once; every link the reader taps leaves the web view.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .other, navigationAction.targetFrame?.isMainFrame != false else {
            if let url = navigationAction.request.url, navigationAction.navigationType == .linkActivated {
                openURL?(url)
            }
            return .cancel
        }
        return .allow
    }
}

/// Forwards script messages without the user content controller retaining the view.
private final class MessageHandler: NSObject, WKScriptMessageHandler {
    var onMessage: ((Any) -> Void)?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage?(message.body)
    }
}

/// Blocks every network load from message bodies until the reader asks for remote content.
final class RemoteContentBlocker {
    static let shared = RemoteContentBlocker()
    private var compiled: WKContentRuleList?

    func ruleList() async throws -> WKContentRuleList? {
        if let compiled { return compiled }
        let rules = #"[{"trigger":{"url-filter":"^(https?|ftp|wss?):"},"action":{"type":"block"}}]"#
        let list = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "goodmail-block-remote", encodedContentRuleList: rules)
        compiled = list
        return list
    }
}

/// Serves `cid:` URLs from the message's inline parts.
final class CIDSchemeHandler: NSObject, WKURLSchemeHandler {
    var message: Message?
    private let attachmentData: (Attachment, Message.ID) async throws -> Data
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(attachmentData: @escaping (Attachment, Message.ID) async throws -> Data) {
        self.attachmentData = attachmentData
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        let contentID = (task.request.url?.absoluteString.dropFirst("cid:".count)).map(String.init)?
            .removingPercentEncoding
        guard let message, let attachment = message.attachments.first(where: { $0.contentID == contentID }) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        running[key] = Task {
            defer { running[key] = nil }
            do {
                let data = try await attachmentData(attachment, message.id)
                guard !Task.isCancelled, let url = task.request.url else { return }
                task.didReceive(
                    URLResponse(
                        url: url, mimeType: attachment.mimeType, expectedContentLength: data.count,
                        textEncodingName: nil))
                task.didReceive(data)
                task.didFinish()
            } catch {
                if !Task.isCancelled { task.didFailWithError(error) }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        running.removeValue(forKey: ObjectIdentifier(task))?.cancel()
    }
}
