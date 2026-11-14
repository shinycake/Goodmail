import MailCore
import Testing
import WebKit

@testable import MailUI

@MainActor
struct QuoteFoldTests {
    @Test func theFoldIsAtLeastATouchTargetInSize() async throws {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 360, height: 600))
        let contents = view.configuration.userContentController
        contents.addUserScript(
            WKUserScript(
                source: MessageScript.source(foldLabel: "Show Quoted Text"), injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        let reported = FirstReport()
        contents.add(reported, name: MessageScript.handlerName)
        view.loadHTMLString(
            MessageDocument.html(
                for: MessageBody(plain: "Sounds good.\n\n> On Monday:\n> Ship it?"), allowsRemoteContent: false),
            baseURL: nil)
        await reported.wait()

        let size = try #require(
            try await view.evaluateJavaScript(
                "(() => { const r = document.querySelector('details.goodmail-fold > summary')"
                    + ".getBoundingClientRect(); return [r.width, r.height]; })()") as? [Double])
        #expect(size[0] >= 44)
        #expect(size[1] >= 44)
    }
}

/// Resumes once the message script reports, which it does after it has folded the quote.
@MainActor
private final class FirstReport: NSObject, WKScriptMessageHandler {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    override init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func wait() async {
        var reports = stream.makeAsyncIterator()
        _ = await reports.next()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        continuation.yield()
    }
}
