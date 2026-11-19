import MailCore
import Testing
import WebKit

@testable import MailUI

@MainActor
struct QuoteFoldTests {
    @Test func theFoldIsAtLeastATouchTargetInSize() async throws {
        let view = await MessageScriptPage.load(
            MessageBody(plain: "Sounds good.\n\n> On Monday:\n> Ship it?"), palette: .adaptive
        ).view

        let size = try #require(
            try await view.evaluateJavaScript(
                "(() => { const r = document.querySelector('details.goodmail-fold > summary')"
                    + ".getBoundingClientRect(); return [r.width, r.height]; })()") as? [Double])
        #expect(size[0] >= 44)
        #expect(size[1] >= 44)
    }

    /// The label comes in through the script's header as a string literal, so a quote, a backslash or a line break in
    /// a translation must reach the page as written rather than end the string.
    @Test func theFoldIsLabeledAsWritten() async throws {
        let label = #"Show "quoted" text \ again"# + "\n" + "הצג טקסט מצוטט"
        let view = await MessageScriptPage.load(
            MessageBody(plain: "Sounds good.\n\n> On Monday:\n> Ship it?"), palette: .adaptive, foldLabel: label
        ).view

        let shown = try await view.evaluateJavaScript(
            "document.querySelector('details.goodmail-fold > summary').getAttribute('aria-label')")
        #expect(shown as? String == label)
    }
}
