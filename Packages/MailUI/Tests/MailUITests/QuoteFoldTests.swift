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
}
