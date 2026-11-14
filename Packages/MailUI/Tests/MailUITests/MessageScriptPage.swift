import MailCore
import WebKit

@testable import MailUI

/// A message body loaded on real WebKit with the message script, for tests of what the script does to the page.
@MainActor
struct MessageScriptPage {
    let view: WKWebView
    /// The height the script first reported, which sizes the card.
    let reportedHeight: Double

    /// Returns once the script has reported, which it does after every pass over the page. The view starts as tall as
    /// `height`; the reader's starts 1 point tall and grows to what the script reports.
    static func load(_ body: MessageBody, palette: MessagePalette, height: Double = 600) async -> MessageScriptPage {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 360, height: height))
        let contents = view.configuration.userContentController
        contents.addUserScript(
            WKUserScript(
                source: MessageScript.source(foldLabel: "Show Quoted Text"), injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        let reports = Reports()
        contents.add(reports, name: MessageScript.handlerName)
        view.loadHTMLString(
            MessageDocument.html(for: body, palette: palette, allowsRemoteContent: false), baseURL: nil)
        return MessageScriptPage(view: view, reportedHeight: await reports.first())
    }
}

/// The heights the message script reports, in order.
@MainActor
private final class Reports: NSObject, WKScriptMessageHandler {
    private let stream: AsyncStream<Double>
    private let continuation: AsyncStream<Double>.Continuation

    override init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func first() async -> Double {
        var reports = stream.makeAsyncIterator()
        return await reports.next() ?? 0
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        continuation.yield((message.body as? [String: Any])?["height"] as? Double ?? 0)
    }
}
