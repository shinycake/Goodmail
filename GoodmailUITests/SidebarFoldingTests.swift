import XCTest

/// A sidebar section folds under its header with a click, and stays folded the next time the app opens.
final class SidebarFoldingTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testASectionFoldsAndStaysFolded() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        var app = launch()
        try XCTSkipUnless(app.windows.firstMatch.horizontalSizeClass == .regular, "a narrow window has no sidebar")
        let header = app.collectionViews["mailboxes"].cells["section.account.synthetic-2"]
        let clients = app.collectionViews["mailboxes"].cells["mailbox.Label_3.synthetic-2"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        // An earlier run may have left it folded.
        if !clients.exists { header.tap() }
        XCTAssertTrue(clients.waitForExistence(timeout: 5))

        header.tap()
        XCTAssertTrue(clients.waitForNonExistence(timeout: 5), "one click folds the section")
        attach(app, "sidebar-folded")

        app.terminate()
        app = launch()
        let headerAgain = app.collectionViews["mailboxes"].cells["section.account.synthetic-2"]
        XCTAssertTrue(headerAgain.waitForExistence(timeout: 5))
        XCTAssertFalse(app.collectionViews["mailboxes"].cells["mailbox.Label_3.synthetic-2"].exists, "still folded")

        headerAgain.tap()
        XCTAssertTrue(
            app.collectionViews["mailboxes"].cells["mailbox.Label_3.synthetic-2"].waitForExistence(timeout: 5),
            "one click unfolds it")
        attach(app, "sidebar-unfolded")
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
