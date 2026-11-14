import MailCore
import Testing
import WebKit

@testable import MailUI

@MainActor
struct MessageFontTests {
    @Test func aFontListWithNoGenericFamilyEndsInTheSystemFont() async throws {
        let body = MessageBody(
            html: """
                <div id="aptos" style="font-family: Aptos">Sent from Outlook</div>\
                <div id="outlook" style="font-family: Aptos, Calibri, Helvetica, sans-serif">Full list</div>\
                <div id="serif" style="font-family: Georgia, serif">Chosen serif</div>
                """)
        let view = await MessageScriptPage.load(body, palette: .adaptive).view
        let script = """
            Object.fromEntries(['aptos', 'outlook', 'serif'].map((id) =>
              [id, getComputedStyle(document.getElementById(id)).fontFamily]))
            """
        let families = try #require(try await view.evaluateJavaScript(script) as? [String: String])
        #expect(families["aptos"]?.hasSuffix("system-ui") == true)
        #expect(families["outlook"]?.hasSuffix("sans-serif") == true, "a list with its own fallback keeps it")
        #expect(families["serif"]?.hasSuffix("serif") == true && families["serif"]?.contains("system-ui") == false)
    }
}
