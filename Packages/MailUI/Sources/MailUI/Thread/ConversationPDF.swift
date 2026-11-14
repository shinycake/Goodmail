import MailCore
import UIKit
import WebKit

/// A conversation as a paged PDF, for printing or sharing: each message laid out by its own off-screen web view
/// (so one sender's styles never reach another's), with the same rules as the reader: no email JavaScript, and no
/// remote loads unless the reader allowed them for that message (ADR-003). WebKit's print formatters are main-actor
/// UI work, so this is too.
@MainActor
enum ConversationPDF {
    /// A page of the reader's region: US Letter where that is the paper, A4 elsewhere, with half-inch margins.
    static var paper: CGRect {
        let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "GT", "CR", "PR"]
        let isLetter = Locale.current.region.map { letterRegions.contains($0.identifier) } ?? false
        return isLetter ? CGRect(x: 0, y: 0, width: 612, height: 792) : CGRect(x: 0, y: 0, width: 595, height: 842)
    }

    static func data(
        for messages: [Message],
        subject: String,
        allowsRemoteContent: Set<Message.ID>,
        attachmentData: @escaping (Attachment, Message.ID) async throws -> Data
    ) async throws -> Data {
        let paper = paper
        let printable = paper.insetBy(dx: 36, dy: 36)
        var pages: [PaperRenderer] = []
        // The web views have to stay alive until their pages are drawn.
        var views: [WKWebView] = []
        for (index, message) in messages.enumerated() {
            try Task.checkCancellation()
            let allows = allowsRemoteContent.contains(message.id)
            let html = PrintDocument.html(
                for: message, subject: index == 0 ? subject : nil,
                dateText: message.date.formatted(date: .long, time: .shortened), allowsRemoteContent: allows)
            let view = try await loadedView(
                html, message: message, width: printable.width, allowsRemoteContent: allows,
                attachmentData: attachmentData)
            views.append(view)
            let renderer = PaperRenderer(paper: paper, printable: printable)
            renderer.addPrintFormatter(view.viewPrintFormatter(), startingAtPageAt: 0)
            pages.append(renderer)
        }
        defer { withExtendedLifetime(views) {} }
        return UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
            for renderer in pages {
                renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
                for page in 0..<renderer.numberOfPages {
                    context.beginPage()
                    renderer.drawPage(at: page, in: paper)
                }
            }
        }
    }

    /// A web view off screen with `html` loaded, its `cid:` images included.
    private static func loadedView(
        _ html: String, message: Message, width: CGFloat, allowsRemoteContent: Bool,
        attachmentData: @escaping (Attachment, Message.ID) async throws -> Data
    ) async throws -> WKWebView {
        let cid = CIDSchemeHandler(attachmentData: attachmentData)
        cid.message = message
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(cid, forURLScheme: "cid")
        if !allowsRemoteContent, let blocker = try? await RemoteContentBlocker.shared.ruleList() {
            configuration.userContentController.add(blocker)
        }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 800), configuration: configuration)
        let loader = PageLoader()
        view.navigationDelegate = loader
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                loader.finished = { continuation.resume(with: $0) }
                view.loadHTMLString(html, baseURL: nil)
            }
        } onCancel: {
            // The handler runs off the main actor. This hop's only effect is to resume the continuation above with
            // a CancellationError, which the awaiting caller owns, so the hop needs no handle of its own.
            Task { @MainActor in loader.cancel(view) }
        }
        view.navigationDelegate = nil
        return view
    }
}

/// Reports when the one document a print view loads has finished, once, and lets nothing else load.
private final class PageLoader: NSObject, WKNavigationDelegate {
    var finished: ((Result<Void, any Error>) -> Void)?

    private func finish(_ result: Result<Void, any Error>) {
        finished?(result)
        finished = nil
    }

    /// Stops the load and resumes the waiting caller with `CancellationError`, unless it already finished.
    func cancel(_ webView: WKWebView) {
        webView.stopLoading()
        finish(.failure(CancellationError()))
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigationAction.navigationType == .other && navigationAction.targetFrame?.isMainFrame != false
            ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        finish(.failure(error))
    }
}

/// Draws onto the given paper, whatever printer is or isn't chosen.
private nonisolated final class PaperRenderer: UIPrintPageRenderer {
    private let paper: CGRect
    private let printable: CGRect

    init(paper: CGRect, printable: CGRect) {
        self.paper = paper
        self.printable = printable
        super.init()
    }

    override var paperRect: CGRect { paper }
    override var printableRect: CGRect { printable }
}
