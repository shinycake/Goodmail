import XCTest

/// Swipe buttons belong to their row: they stay on it when mail arrives above, and a swipe back over them only
/// closes them.
final class SwipeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOpenButtonsStayOnTheirRowWhenMailArrivesAbove() {
        let app = launch(arrivalsEvery: 3)
        let row = firstThread(in: app)
        let before = row.frame
        row.swipeLeft(velocity: .slow)
        let archive = app.buttons["Archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))

        let deadline = Date.now.addingTimeInterval(10)
        while firstThread(in: app).frame.minY <= before.minY, Date.now < deadline {
            RunLoop.current.run(until: .now.addingTimeInterval(0.5))
        }
        let after = firstThread(in: app).frame
        XCTAssertGreaterThan(after.minY, before.minY, "mail arrived above the swiped row")
        XCTAssertTrue(archive.exists, "the buttons stayed open")
        XCTAssertTrue(after.contains(CGPoint(x: archive.frame.midX, y: archive.frame.midY)), "on their row")
        attach(app, "swipe-after-arrival")
    }

    @MainActor
    func testSwipingBackOverOpenButtonsOnlyClosesThem() {
        let app = launch()
        let row = firstThread(in: app)
        row.swipeLeft(velocity: .slow)
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5))

        row.swipeRight(velocity: .slow)
        XCTAssertTrue(app.buttons["Archive"].waitForNonExistence(timeout: 5), "the trailing buttons closed")
        XCTAssertFalse(app.buttons["Star"].exists || app.buttons["Unstar"].exists, "the leading ones stayed hidden")

        row.swipeRight(velocity: .slow)
        XCTAssertTrue(
            app.buttons["Star"].waitForExistence(timeout: 5) || app.buttons["Unstar"].exists,
            "a fresh swipe reveals the leading buttons")
        attach(app, "swipe-leading")
    }

    @MainActor
    private func launch(arrivalsEvery interval: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GoodmailSyntheticThreads", "200", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let interval { app.launchArguments += ["-GoodmailSyntheticArrivalEvery", "\(interval)"] }
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    /// The first thread row; section headers are cells too, so it's picked by what it says.
    @MainActor
    private func firstThread(in app: XCUIApplication) -> XCUIElement {
        app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS 'Lunch tomorrow?'"))
            .firstMatch
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
