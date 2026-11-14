import MailCore
import Testing
import WebKit

@testable import MailUI

/// The script sizes the card from the body's content, starting from the reader's 1-point-tall view.
@MainActor
struct MessageHeightTests {
    /// Templates such as Stack Exchange's hold `html` and `body` to the view's height, which once kept the card at
    /// 1 point: a thin line and no message.
    @Test(arguments: MessagePalette.allCases)
    func aBodyHeldToTheViewsHeightStillSizesTheCardToItsContent(palette: MessagePalette) async {
        let body = MessageBody(
            html: """
                <html><head><style>html, body { margin: 0 auto !important; padding: 0 !important; \
                height: 100% !important; width: 100% !important; }</style></head>\
                <body style="height: 100%"><table width="100%" height="100%" bgcolor="#f1f2f3"><tr><td>\
                <h1>1 new item in your inbox</h1><p>The following item was added to your inbox.</p>\
                <p>You are now able to set your unique username for your profile.</p>\
                <p>See all of your inbox items.</p></td></tr></table></body></html>
                """)
        let page = await MessageScriptPage.load(body, palette: palette, height: 1)
        #expect(page.reportedHeight > 150)
    }

    @Test func aPlainBodyIsAsTallAsItsText() async {
        let short = await MessageScriptPage.load(MessageBody(plain: "Thanks!"), palette: .adaptive, height: 1)
        let long = await MessageScriptPage.load(
            MessageBody(plain: Array(repeating: "A line of the reply.", count: 10).joined(separator: "\n")),
            palette: .adaptive, height: 1)
        #expect(short.reportedHeight > 10 && short.reportedHeight < 60)
        #expect(long.reportedHeight > short.reportedHeight * 5)
    }
}
