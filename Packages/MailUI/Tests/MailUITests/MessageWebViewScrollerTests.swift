import Testing
import UIKit
import WebKit

@testable import MailUI

/// A letter's card grows to fit its body, so its web view never scrolls and shows no scrollers, which a Mac would
/// otherwise draw at the card's edge.
@MainActor
struct MessageWebViewScrollerTests {
    @Test func aLetterShowsNoScrollers() throws {
        let view = MessageWebView(attachmentData: { _, _ in Data() })
        let webView = try #require(Self.webView(in: view))
        #expect(!webView.scrollView.showsVerticalScrollIndicator)
        #expect(!webView.scrollView.showsHorizontalScrollIndicator)
    }

    private static func webView(in view: UIView) -> WKWebView? {
        for subview in view.subviews {
            if let found = subview as? WKWebView ?? webView(in: subview) { return found }
        }
        return nil
    }
}
