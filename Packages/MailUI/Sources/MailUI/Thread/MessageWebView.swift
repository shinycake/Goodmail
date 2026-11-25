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
    /// The reader's zoom this view last asked its page for. The page reports the zoom it is at with each height, so a
    /// request that reached it before its script ran is sent again.
    private var appliedZoom = ReaderZoomModel.shared.zoom
    /// The content shown and its load. A newer `show` cancels one still preparing, so a slow first rule compile can't
    /// load stale content, and script messages count only from the newest load's commit on.
    private var body = BodyLoad<Content, WKNavigation>.blank {
        didSet { preview.isHidden = previewText == nil }
    }
    /// The link under the pointer as this body last reported it, which a page that goes away never takes back.
    private var hoveredLink: URL?

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
        // The card grows to fit the body, so there's nothing to scroll, and a Mac would still draw its scrollers.
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        messageHandler.onMessage = { [weak self] report in self?.handle(report) }
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

    isolated deinit {
        body.cancel()
    }

    func show(_ content: Content) {
        guard content != body.content else { return }
        // Loading remote images keeps the body that shows; only another message starts from its words.
        let sameMessage = content.message.id == body.content?.message.id
        if !sameMessage { preview.setContentText(ReplyText(body: content.message.body).text) }
        cidHandler.message = content.message
        // The page going away takes the link under the pointer with it, and it says nothing as it goes.
        leaveLink()
        body.show(content, sameMessage: sameMessage, work: prepare(content))
    }

    /// Builds the content's document and loads it.
    private func prepare(_ content: Content) -> Task<Void, Never> {
        Task { [weak self] in
            async let document = Self.document(
                for: content.message.body, allowsRemoteContent: content.allowsRemoteContent)
            let blocker = content.allowsRemoteContent ? nil : await RemoteContentBlocker.shared.ruleList()
            let (html, palette) = await document
            guard !Task.isCancelled, let self else { return }
            let rules = webView.configuration.userContentController
            rules.removeAllContentRuleLists()
            if let blocker { rules.add(blocker) }
            // A painted body is a sheet of its own on the card, so it gets the card's rounded corners.
            webView.layer.cornerRadius = palette == .painted ? 12 : 0
            guard let navigation = webView.loadHTMLString(MessageDocument.zoomed(html, by: appliedZoom), baseURL: nil)
            else { return }
            body.load(navigation)
        }
    }

    /// The load of the content shown failed or its page went: it loads once more.
    private func reload() {
        let now = ContinuousClock.now
        guard let content = body.reloadable(at: now) else { return }
        body.reload(work: prepare(content), at: now)
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
    var previewText: String? {
        guard body.showsPreview, let words = preview.text, !words.isEmpty else { return nil }
        return words
    }

    /// Takes what the script reports: the body's height, whether it blocked remote content, or a link under the
    /// pointer. Only the page of the content shown reports; what an older page says is about content no longer shown.
    func handle(_ report: Any) {
        switch MessageReport(report) {
        case .layout(let height, let hasRemote, let zoom):
            guard let content = body.laidOut() else { return }
            heightConstraint.constant = max(1, height)
            if zoom != appliedZoom.factor { sendZoom() }
            onLayout?(heightConstraint.constant, hasRemote && !content.allowsRemoteContent)
        case .hover(let link?):
            // A touch window's tap on a link would report a hover that never ends.
            guard body.reporting != nil, traitCollection.interactionStyle == .desktop else { return }
            hoveredLink = link
            onHoverLink?(link)
        case .hover(nil):
            // Leaving a link is true of any page, the one going too.
            leaveLink()
        case nil:
            break
        }
    }

    /// The pointer left the link this body last reported, if any.
    private func leaveLink() {
        guard hoveredLink != nil else { return }
        hoveredLink = nil
        onHoverLink?(nil)
    }

    /// The reader's zoom is a setting of this device that every message view follows (`ReaderZoomModel`).
    override func updateProperties() {
        super.updateProperties()
        let zoom = ReaderZoomModel.shared.zoom
        guard zoom != appliedZoom else { return }
        appliedZoom = zoom
        sendZoom()
    }

    /// Asks the page for the reader's zoom. It reflows and reports its new height, and a page whose script hasn't run
    /// yet reports the zoom it has once it does, which brings this view back here.
    private func sendZoom() {
        webView.evaluateJavaScript(MessageScript.zoom(to: appliedZoom), in: nil, in: PreparedWebView.world)
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
        // The page's zoom leaves its boxes in the view's points.
        let inWebView = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
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

    /// WebKit passes no navigation for a load it starts itself, which is never the body's.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let navigation else { return }
        body.commit(navigation)
    }

    /// The body's page never came: it loads once more rather than stay without a height.
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        guard let navigation, body.awaits(navigation) else { return }
        reload()
    }

    /// The content process went, and the page with it, as under memory pressure, taking any link under the pointer.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        leaveLink()
        reload()
    }
}
