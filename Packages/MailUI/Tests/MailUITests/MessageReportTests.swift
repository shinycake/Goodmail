import Foundation
import Testing

@testable import MailUI

/// What a message's script says, as the app reads it.
struct MessageReportTests {
    @Test func aHeightIsALayout() {
        #expect(
            MessageReport(["height": 420.0, "hasRemote": true, "zoom": 1.5])
                == .layout(height: 420, hasRemoteContent: true, zoom: 1.5))
        #expect(MessageReport(["height": 10.0]) == .layout(height: 10, hasRemoteContent: false, zoom: 1))
    }

    @Test func aLinkIsAHover() {
        #expect(MessageReport(["link": "https://example.com/a"]) == .hover(link: URL(string: "https://example.com/a")))
    }

    @Test func aNullLinkIsThePointerLeaving() {
        #expect(MessageReport(["link": NSNull()]) == .hover(link: nil))
    }

    @Test func anythingElseIsIgnored() {
        #expect(MessageReport(["other": 1]) == nil)
        #expect(MessageReport("height") == nil)
    }
}
