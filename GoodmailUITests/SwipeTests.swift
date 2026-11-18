import XCTest

/// Swipe buttons belong to their row: they stay on it when mail arrives above, and a swipe back over them only
/// closes them.
final class SwipeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOpenButtonsStayOnTheirRowWhenMailArrivesAbove() {
        let app = launch(arrivalsEvery: 4)
        let row = firstThread(in: app)
        let before = row.frame
        let archive = app.buttons["Archive"]
        swipeOpen(row, showing: archive)

        // Reads the row and the button between arrivals, once the list has stopped moving: frames read during the
        // insert animation, or across the next arrival, would compare two different moments.
        var settled: (row: CGRect, button: CGRect)?
        let deadline = Date.now.addingTimeInterval(15)
        while settled == nil, Date.now < deadline {
            RunLoop.current.run(until: .now.addingTimeInterval(0.4))
            let row = firstThread(in: app).frame
            let button = archive.frame
            guard row.minY > before.minY, archive.exists else { continue }
            RunLoop.current.run(until: .now.addingTimeInterval(0.4))
            if firstThread(in: app).frame == row, archive.frame == button { settled = (row, button) }
        }
        guard let settled else { return XCTFail("mail arrived above the swiped row, with its buttons still open") }
        XCTAssertTrue(settled.row.contains(CGPoint(x: settled.button.midX, y: settled.button.midY)), "on their row")
        attach(app, "swipe-after-arrival")
    }

    @MainActor
    func testSwipingBackOverOpenButtonsOnlyClosesThem() {
        let app = launch()
        let row = firstThread(in: app)
        swipeOpen(row, showing: app.buttons["Archive"])

        swipeRight(row, in: app)
        XCTAssertTrue(app.buttons["Archive"].waitForNonExistence(timeout: 5), "the trailing buttons closed")
        XCTAssertFalse(app.buttons["Star"].exists || app.buttons["Unstar"].exists, "the leading ones stayed hidden")

        swipeRight(row, in: app)
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

    /// Swipes `row` left until `button` shows. On a busy machine a synthesized swipe sometimes arrives too short or
    /// too slow to pass halfway, and the row rightly springs back; that's the input, not the behavior under test.
    @MainActor
    private func swipeOpen(_ row: XCUIElement, showing button: XCUIElement) {
        for _ in 0..<3 {
            row.swipeLeft(velocity: .slow)
            if button.waitForExistence(timeout: 3) { return }
        }
        XCTFail("the swipe never opened the row's buttons")
    }

    /// Swipes `row` right from the part of it on show. On iPad the sidebar floats over the list's leading edge, and a
    /// swipe that starts under it lands on the sidebar, not the row. There the drag starts just past the sidebar and
    /// stops short of a full swipe, which would run the first action instead of showing the buttons.
    @MainActor
    private func swipeRight(_ row: XCUIElement, in app: XCUIApplication) {
        let sidebar = app.navigationBars["Mailboxes"]
        guard sidebar.exists, sidebar.frame.maxX > row.frame.minX else { return row.swipeRight(velocity: .slow) }
        let start = (sidebar.frame.maxX + 16 - row.frame.minX) / row.frame.width
        row.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
            .press(
                forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: start + 0.3, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0)
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
