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
    /// The link the pointer is over, or `nil` once it leaves. Only a desktop window reports it.
    var onHoverLink: ((URL?) -> Void)?

    private let webView: WKWebView
    /// The message's new words, shown at once while the web view starts, which can take seconds; the first height
    /// it reports replaces them.
    private let preview = UILabel()
    private let messageHandler: MessageHandler
    private let cidHandler: CIDSchemeHandler
    private var heightConstraint: NSLayoutConstraint!
    /// The body's height as the page measures it, before the reader's zoom scales it into points.
    private var contentHeight: CGFloat = 1
    private var appliedZoom = ReaderZoom.standard
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

    /// Takes what the script reports: the body's height, whether it blocked remote content, or a link under the pointer.
    func handle(_ body: Any) {
        switch MessageReport(body) {
        case .layout(let height, let hasRemote):
            contentHeight = height
            sizeToContent()
            preview.isHidden = true
            onLayout?(heightConstraint.constant, hasRemote && content?.allowsRemoteContent == false)
        case .hover(let link):
            // A touch window's tap on a link would report a hover that never ends.
            if traitCollection.interactionStyle == .desktop { onHoverLink?(link) }
        case nil:
            break
        }
    }

    /// The reader's zoom is a setting of this device that every message view follows (`ReaderZoomModel`).
    override func updateProperties() {
        super.updateProperties()
        let zoom = ReaderZoomModel.shared.zoom
        guard zoom != appliedZoom else { return }
        appliedZoom = zoom
        webView.pageZoom = zoom.factor
        sizeToContent()
    }

    /// The page lays out in its own units, which the zoom scales into points; the page reports again once the new
    /// width has reflowed it.
    private func sizeToContent() {
        heightConstraint.constant = max(1, contentHeight * appliedZoom.factor)
    }

    /// Finds the next match of `query` in this message and returns its box in this view's coordinates, or `nil` when
    /// it has none from the current match on. A match the page can't place is given the message's top.
    func findMatch(_ query: String, backwards: Bool) async -> CGRect? {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        // Wrapping is the find bar's call: it tries the other messages first (`FindOrder`).
        configuration.wraps = false
        guard let result = try? await webView.find(query, configuration: configuration), result.matchFound else {
            return nil
        }
        let box = try? await webView.evaluateJavaScript(
            "window.goodmailFind.matchBox()", contentWorld: PreparedWebView.world)
        guard let numbers = box as? [Double], numbers.count == 4 else {
            return CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        }
        let scale = webView.pageZoom
        let inWebView = CGRect(
            x: numbers[0] * scale, y: numbers[1] * scale, width: numbers[2] * scale, height: numbers[3] * scale)
        return webView.convert(inWebView, to: self)
    }

    /// Forgets the match this message shows.
    func clearMatch() async {
        _ = try? await webView.evaluateJavaScript(
            "window.goodmailFind.clear()", contentWorld: PreparedWebView.world)
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
