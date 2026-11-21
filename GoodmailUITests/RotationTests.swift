import XCTest

/// Turning an iPad mid-read keeps what the reader was doing: the search and its results, and the conversation open
/// beside them, the same screens rather than new ones (D8).
final class RotationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testTurningMidReadKeepsTheSearchAndTheReader() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "an iPad turns between widths")
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "40", "-GoodmailSyntheticArrivalEvery", "3600",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))

        let search = app.navigationBars.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("plans")
        let result = app.cells.containing(NSPredicate(format: "label CONTAINS 'Weekend plans'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "search finds it")
        XCTAssertTrue(
            retry({ result.tap() }, until: { app.scrollViews["thread"].exists }), "the conversation opens")
        let subject = app.staticTexts["thread.subject"]
        XCTAssertTrue(waitUntil { subject.exists && subject.label == "Weekend plans" })

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(
                waitUntil { subject.exists && subject.label == "Weekend plans" }, "the reader stays, \(orientation)")
            XCTAssertTrue(field.exists, "the search stays")
            XCTAssertEqual(field.value as? String, "plans", "with what was typed")
            XCTAssertTrue(result.exists, "and its results")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "rotation-\(orientation == .portrait ? "portrait" : "landscape")"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
