import XCTest

/// The body as it is written in Dark Mode: text in the reader's own color shows light on the dark page, and a color
/// from the picker colors what is typed next.
final class ComposeDarkModeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheReadersOwnColorShowsLightOnTheDarkPage() throws {
        let app = launch()
        let body = writeBody("בדיקה", in: app)
        attach(app, "dark-default")
        let brightest = try XCTUnwrap(brightestLuminance(in: body.screenshot().image))
        XCTAssertGreaterThan(brightest, 0.8, "the text is light, not near-black on the dark page")
    }

    @MainActor
    func testAPickedColorColorsWhatIsTypedNext() {
        let app = launch()
        let body = writeBody("בדיקה ", in: app)
        app.buttons["Text Color"].tap()
        let more = app.buttons["More Colors…"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "the color menu opens")
        attach(app, "dark-color-menu")
        more.tap()
        // The picker runs in its own process, so its controls are found by where they are.
        settle()
        attach(app, "dark-picker")
        // A dark navy from the grid, too dark to read on a dark page as it is.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.645)).tap()
        settle()
        attach(app, "dark-picker-chosen")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        settle()
        body.typeText("colored")
        attach(app, "dark-colored")
        XCUIDevice.shared.appearance = .light
        settle()
        attach(app, "light-colored")
    }

    private func settle() {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settles")], timeout: 1.5)
    }

    @MainActor
    private func writeBody(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.toolbars.buttons["New Message"].tap()
        let body = app.textViews["compose.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5), "the composer opens")
        body.tap()
        body.typeText(text)
        return body
    }

    /// The relative luminance of the brightest pixel, from 0 to 1.
    private func brightestLuminance(in image: UIImage) -> CGFloat? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            // Unsafe because the context writes through the buffer's pointer. Safe: it lives only inside this closure,
            // over a buffer sized for every pixel it draws.
            guard
                let context = unsafe CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var brightest: CGFloat = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let luminance =
                (0.2126 * CGFloat(pixels[index]) + 0.7152 * CGFloat(pixels[index + 1]) + 0.0722
                    * CGFloat(pixels[index + 2])) / 255
            brightest = max(brightest, luminance)
        }
        return brightest
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        XCUIDevice.shared.appearance = .dark
        addTeardownBlock { @MainActor in XCUIDevice.shared.appearance = .light }
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-GoodmailSyntheticArrivalEvery",
            "3600", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
