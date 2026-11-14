import MailCore
import UIKit
import WebKit

/// A conversation as a paged PDF, for printing or sharing: each message laid out by its own off-screen web view
/// (so one sender's styles never reach another's), with the same rules as the reader: no email JavaScript, and no
/// remote loads unless the reader allowed them for that message (ADR-003). Each web view renders its message as one
/// tall PDF page (`WKWebView.pdf`), which is cut into paper-sized pages. WebKit's print formatter isn't used: in the
/// app it waits on the web process of a view that isn't in a window, holding the main thread forever.
@MainActor
enum ConversationPDF {
    enum Failure: Error {
        /// WebKit's PDF of a message couldn't be read back, so the conversation would print without it.
        case unreadableMessagePDF
    }

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
        // One tall page per message, kept with its document: a CGPDFPage doesn't keep the document it came from.
        var rendered: [(document: CGPDFDocument, page: CGPDFPage)] = []
        for (index, message) in messages.enumerated() {
            try Task.checkCancellation()
            let allows = allowsRemoteContent.contains(message.id)
            let html = PrintDocument.html(
                for: message, subject: index == 0 ? subject : nil,
                dateText: message.date.formatted(date: .long, time: .shortened), allowsRemoteContent: allows)
            let view = try await loadedView(
                html, message: message, width: printable.width, allowsRemoteContent: allows,
                attachmentData: attachmentData)
            let pdf = try await view.pdf(configuration: WKPDFConfiguration())
            // WebKit returned a PDF, so it parses; if it ever doesn't, the export fails rather than drop a message.
            guard let document = CGDataProvider(data: pdf as CFData).flatMap(CGPDFDocument.init),
                let page = document.page(at: 1)
            else { throw Failure.unreadableMessagePDF }
            rendered.append((document, page))
        }
        return UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
            for message in rendered {
                draw(message.page, onto: context, printable: printable)
            }
        }
    }

    /// Cuts one tall page into as many paper pages as it fills, each showing the next slice in the printable area.
    private static func draw(_ page: CGPDFPage, onto context: UIGraphicsPDFRendererContext, printable: CGRect) {
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return }
        let scale = printable.width / box.width
        let height = box.height * scale
        var offset: CGFloat = 0
        repeat {
            context.beginPage()
            let cg = context.cgContext
            cg.saveGState()
            cg.clip(to: printable)
            // PDF space runs up from the bottom; the page's top goes `offset` above the printable area's top.
            cg.translateBy(x: printable.minX, y: printable.minY - offset + height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -box.minX, y: -box.minY)
            cg.drawPDFPage(page)
            cg.restoreGState()
            offset += printable.height
        } while offset < height
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
        // A rule list that fails to compile is left out: the document's content security policy still blocks
        // remote loads, so the block fails closed, as in the reader.
        if !allowsRemoteContent, let blocker = try? await RemoteContentBlocker.shared.ruleList() {
            configuration.userContentController.add(blocker)
        }
        // As short as can be, so the content sets the height of its PDF and no blank paper follows a short message.
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 1), configuration: configuration)
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
