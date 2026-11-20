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
        let pixels = try XCTUnwrap(Self.pixels(in: body.screenshot().image))
        XCTAssertGreaterThan(pixels.map(\.luminance).max() ?? 0, 0.8, "the text is light, not near-black on the page")
    }

    @MainActor
    func testAPickedColorColorsWhatIsTypedNext() throws {
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
        let pixels = try XCTUnwrap(Self.pixels(in: body.screenshot().image))
        // The word draws about 1,800 colored pixels; its first letter and the caret together, about 500.
        let colored = pixels.filter { $0.saturation > 0.4 }
        XCTAssertGreaterThan(colored.count, 1200, "the whole word is colored, not only its first letter")
        XCTAssertGreaterThan(
            colored.map(\.luminance).max() ?? 0, 0.15, "the navy was brightened to read on the dark page")
        XCUIDevice.shared.appearance = .light
        settle()
        attach(app, "light-colored")
    }

    /// The picker runs in another process, so the test can't wait on its controls: it gives each step time instead.
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

    private struct Pixel {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat

        var luminance: CGFloat { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
        var saturation: CGFloat { max(red, green, blue) - min(red, green, blue) }
    }

    /// Every pixel of `image`, components from 0 to 1.
    private static func pixels(in image: UIImage) -> [Pixel]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
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
        var pixels: [Pixel] = []
        pixels.reserveCapacity(width * height)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let red = CGFloat(bytes[index]) / 255
            let green = CGFloat(bytes[index + 1]) / 255
            let blue = CGFloat(bytes[index + 2]) / 255
            pixels.append(Pixel(red: red, green: green, blue: blue))
        }
        return pixels
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
