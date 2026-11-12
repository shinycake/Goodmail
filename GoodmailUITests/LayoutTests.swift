import XCTest

/// A thread opens beside its list in a wide window and on top of it in a narrow one; a wide window also keeps the
/// mailboxes in a sidebar. Runs on whichever simulator the tests target, and attaches what it saw.
final class LayoutTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testOpeningAThread() {
        let app = launch()
        let list = app.collectionViews["mailbox"]
        // Section headers are cells too, so pick a thread row by what it says.
        list.cells.containing(NSPredicate(format: "label CONTAINS 'Lunch tomorrow?'")).firstMatch.tap()
        XCTAssertTrue(app.scrollViews["thread"].waitForExistence(timeout: 5))
        attach(app, "thread-open")

        if app.windows.firstMatch.horizontalSizeClass == .regular {
            XCTAssertTrue(list.isHittable, "the list stays beside the thread")
        } else {
            XCTAssertFalse(list.isHittable, "the thread covers the list")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(list.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testTheSidebarSwitchesMailboxes() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch()
        try XCTSkipUnless(app.windows.firstMatch.horizontalSizeClass == .regular, "a narrow window has no sidebar")
        let sent = app.collectionViews["mailboxes"].cells["mailbox.SENT"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5), "the sidebar shows in a wide landscape window")
        sent.tap()
        XCTAssertTrue(app.staticTexts["No Message Selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(sent.isSelected, "the open mailbox stays selected in the sidebar")
        attach(app, "sidebar-sent")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GoodmailSyntheticThreads", "200", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
