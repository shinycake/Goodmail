import MailCore
import Testing
import WebKit

@testable import MailUI

/// A message body loaded on real WebKit with the message script, for tests of what the script does to the page.
@MainActor
struct MessageScriptPage {
    let view: WKWebView
    /// The height the script first reported, which sizes the card.
    let reportedHeight: Double
    private let reports: Reports

    /// Returns once the script has reported, which it does after every pass over the page. The view starts as tall as
    /// `height`; the reader's starts 1 point tall and grows to what the script reports. A view out of a window
    /// follows the system's appearance, so a test that needs one forces it in the page, as the PDF does.
    static func load(
        _ body: MessageBody, palette: MessagePalette, height: Double = 600, appearance: ForcedAppearance? = nil,
        foldLabel: String = "Show Quoted Text", zoom: ReaderZoom = .standard
    ) async -> MessageScriptPage {
        let forced = { (text: String) in appearance.map { $0.apply(to: text) } ?? text }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 360, height: height))
        let contents = view.configuration.userContentController
        contents.addUserScript(
            WKUserScript(
                source: forced(MessageScript.source(for: .reader(foldLabel: foldLabel))),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        let reports = Reports()
        contents.add(reports, name: MessageScript.handlerName)
        let document = MessageDocument.zoomed(
            MessageDocument.html(for: body, palette: palette, allowsRemoteContent: false), by: zoom)
        view.loadHTMLString(
            forced(MessageDocument.inject(head: appearance?.rootStyle ?? "", into: document)), baseURL: nil)
        return MessageScriptPage(view: view, reportedHeight: await reports.next(), reports: reports)
    }

    /// Zooms the loaded page as the reader does, and returns the height the script reports for it.
    func zoom(to zoom: ReaderZoom) async throws -> Double {
        _ = try await view.evaluateJavaScript(MessageScript.zoom(to: zoom))
        return await reports.next()
    }

    /// How wide a word set in the letter's own text draws, as the reader sees it.
    func wordWidth() async throws -> Double {
        let measure = """
            (() => { const word = document.createElement('span'); word.textContent = 'Thursday';
            document.body.append(word); const width = word.getBoundingClientRect().width; word.remove(); return width; })()
            """
        return try #require(try await view.evaluateJavaScript(measure) as? Double)
    }
}

/// The heights the message script reports, in order.
@MainActor
private final class Reports: NSObject, WKScriptMessageHandler {
    private let continuation: AsyncStream<Double>.Continuation
    private var reports: AsyncStream<Double>.Iterator

    override init() {
        let (stream, continuation) = AsyncStream<Double>.makeStream()
        self.continuation = continuation
        reports = stream.makeAsyncIterator()
    }

    /// The next height the script reports.
    /// The stream's iterator shares the stream's buffer, so a copy moves it on for the next call too.
    func next() async -> Double {
        var iterator = reports
        let height = await iterator.next(isolation: #isolation) ?? 0
        reports = iterator
        return height
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        continuation.yield((message.body as? [String: Any])?["height"] as? Double ?? 0)
    }
}
