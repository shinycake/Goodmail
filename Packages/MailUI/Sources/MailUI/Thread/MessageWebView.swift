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
    /// The message's new words, shown at once while the web view starts, which can take seconds; the first height
    /// it reports replaces them.
    private let preview = UILabel()
    private let messageHandler: MessageHandler
    private let cidHandler: CIDSchemeHandler
    private var heightConstraint: NSLayoutConstraint!
    private var content: Content?
    /// Applies the latest `show`. A newer one cancels it, so a slow first rule compile can't load stale content.
    private var loading: Task<Void, Never>?
    /// The load of the content shown now. Script messages count from its commit on, so a spare's blank body, still
    /// loading when this view took it, can't report a height.
    private var navigation: WKNavigation?

    /// `attachmentData` fetches a part a `cid:` URL names.
    init(attachmentData: @escaping (Attachment, Message.ID) async throws -> Data) {
        let prepared = MessageWebViewPool.shared.take()
        webView = prepared.webView
        messageHandler = prepared.messageHandler
        cidHandler = prepared.cidHandler
        cidHandler.attachmentData = attachmentData
        super.init(frame: .zero)

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.clipsToBounds = true
        webView.layer.cornerCurve = .continuous
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        preview.font = .preferredFont(forTextStyle: .body)
        preview.adjustsFontForContentSizeCategory = true
        preview.numberOfLines = 8
        preview.isHidden = true
        let stack = UIStackView(arrangedSubviews: [preview, webView])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        heightConstraint = webView.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func show(_ content: Content) {
        guard content != self.content else { return }
        // Loading remote images keeps the body that shows; only another message starts from its words.
        if content.message.id != self.content?.message.id {
            let words = ReplyText(body: content.message.body).text
            preview.setContentText(words)
            preview.isHidden = words.isEmpty
        }
        self.content = content
        cidHandler.message = content.message
        loading?.cancel()
        loading = Task {
            async let document = Self.document(
                for: content.message.body, allowsRemoteContent: content.allowsRemoteContent)
            let blocker = content.allowsRemoteContent ? nil : await RemoteContentBlocker.shared.ruleList()
            let (html, palette) = await document
            guard !Task.isCancelled else { return }
            let rules = webView.configuration.userContentController
            rules.removeAllContentRuleLists()
            if let blocker { rules.add(blocker) }
            // A painted body is a sheet of its own on the card, so it gets the card's rounded corners.
            webView.layer.cornerRadius = palette == .painted ? 12 : 0
            navigation = webView.loadHTMLString(html, baseURL: nil)
        }
    }

    /// Picking the palette and building the document read the whole body, so they stay off the main actor.
    @concurrent
    private nonisolated static func document(
        for body: MessageBody, allowsRemoteContent: Bool
    ) async -> (String, MessagePalette) {
        let palette = MessagePalette.of(body)
        let html = MessageDocument.html(for: body, palette: palette, allowsRemoteContent: allowsRemoteContent)
        return (html, palette)
    }

    /// The words that show while the body loads, or nil once it has its height.
    var previewText: String? { preview.isHidden ? nil : preview.text }

    /// Takes what the script reports: the body's height, and whether it blocked remote content.
    func handle(_ body: Any) {
        guard let body = body as? [String: Any], let height = body["height"] as? Double else { return }
        heightConstraint.constant = max(1, height)
        preview.isHidden = true
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

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        messageHandler.onMessage = { [weak self] body in self?.handle(body) }
    }
}
