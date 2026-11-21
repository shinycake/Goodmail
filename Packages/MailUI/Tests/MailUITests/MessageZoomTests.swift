import MailCore
import Testing
import WebKit

@testable import MailUI

/// The reader's zoom scales the letter itself: its text reflows larger, and the card grows to match.
@MainActor
struct MessageZoomTests {
    private let body = MessageBody(
        plain: Array(repeating: "A line of the reply that is long enough to wrap in the card.", count: 6)
            .joined(separator: "\n"))
    private let larger = ReaderZoom.standard.zoomedIn().zoomedIn().zoomedIn()

    @Test("A letter that loads zoomed in is taller than one at actual size")
    func loadsZoomed() async {
        let actual = await MessageScriptPage.load(body, palette: .adaptive, height: 1)
        let zoomed = await MessageScriptPage.load(body, palette: .adaptive, height: 1, zoom: larger)
        #expect(zoomed.reportedHeight > actual.reportedHeight * larger.factor * 0.9)
    }

    @Test("Zooming a letter on show reports its new height, and Actual Size brings it back")
    func zoomsOnShow() async throws {
        let page = await MessageScriptPage.load(body, palette: .adaptive, height: 1)
        let zoomed = try await page.zoom(to: larger)
        #expect(zoomed > page.reportedHeight * larger.factor * 0.9)
        #expect(try await page.zoom(to: .standard) == page.reportedHeight)
    }

    @Test("Zooming scales the letter's text, and zooming out and Actual Size shrink it back")
    func scalesText() async throws {
        let page = await MessageScriptPage.load(body, palette: .adaptive, height: 1)
        let actual = try await page.wordWidth()
        _ = try await page.zoom(to: larger)
        #expect(try await page.wordWidth() > actual * larger.factor * 0.9)
        _ = try await page.zoom(to: larger.zoomedOut())
        let smaller = try await page.wordWidth()
        #expect(smaller > actual && smaller < actual * larger.factor * 0.9)
        _ = try await page.zoom(to: .standard)
        #expect(abs(try await page.wordWidth() - actual) < 0.5)
    }
}
