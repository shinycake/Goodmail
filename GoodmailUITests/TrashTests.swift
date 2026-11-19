import XCTest

/// Delete Forever in Trash: it always asks first, and Select with nothing picked offers Empty Trash.
final class TrashTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDeleteForeverAsksFirstThenTakesTheThreadAway() {
        let app = openTrash()
        let list = app.collectionViews["mailbox"]
        let count = list.cells.count
        let deleteForever = app.buttons["Delete Forever"]
        XCTAssertTrue(list.cells.element(boundBy: 1).swipeOpen(showing: deleteForever))
        XCTAssertTrue(app.buttons["Move Out of Trash"].exists)
        attach(app, "trash-swipe")

        deleteForever.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Delete Thread Forever?"].exists)
        attach(app, "trash-delete-forever-alert")
        alert.buttons["Cancel"].tap()
        XCTAssertEqual(list.cells.count, count, "Cancel keeps the thread")

        XCTAssertTrue(list.cells.element(boundBy: 1).swipeOpen(showing: deleteForever))
        deleteForever.tap()
        app.alerts.firstMatch.buttons["Delete Forever"].tap()
        let gone = NSPredicate { _, _ in list.cells.count < count }
        wait(for: [XCTNSPredicateExpectation(predicate: gone, object: nil)], timeout: 10)
    }

    @MainActor
    func testSelectingNothingInTrashOffersEmptyTrash() {
        let app = openTrash()
        app.navigationBars.buttons["Select"].tap()
        let empty = app.toolbars.buttons["Empty Trash"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.isEnabled)
        attach(app, "trash-select")

        empty.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Empty Trash?"].exists)
        attach(app, "trash-empty-alert")
        alert.buttons["Empty Trash"].tap()
        XCTAssertTrue(app.staticTexts["No Mail"].waitForExistence(timeout: 10), "Trash is empty")
        attach(app, "trash-emptied")
        let bar = app.navigationBars.firstMatch
        XCTAssertFalse(bar.buttons["Done"].exists, "Emptying Trash ends selecting")
        XCTAssertFalse(bar.buttons["Select"].exists, "An empty list has nothing to select")
        XCTAssertTrue(bar.buttons["Search"].exists, "Search stays")
    }

    @MainActor
    private func openTrash() -> XCUIApplication {
        let app = XCUIApplication()
        // A mailbox taking arrivals is seeded fresh each launch, so what an earlier run deleted is back. None arrive
        // within the test.
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "40", "-GoodmailSyntheticArrivalEvery", "3600",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        let trash = app.collectionViews["mailboxes"].cells["mailbox.TRASH"].firstMatch
        // On a phone the mailboxes are behind the list; on iPad the sidebar already shows them.
        if !trash.isHittable { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.tap()
        XCTAssertTrue(app.navigationBars["Trash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.collectionViews["mailbox"].cells.element(boundBy: 1).waitForExistence(timeout: 10))
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
