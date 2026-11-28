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
        let sidebar = app.collectionViews["mailboxes"]
        let header = sidebar.cells["section.account.synthetic-2"]
        let clients = sidebar.cells["mailbox.Label_3.synthetic-2"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        // The second account's section sits below every account's own mailboxes.
        scroll(sidebar, toReveal: header)
        // An earlier run may have left it folded.
        if !scroll(sidebar, toReveal: clients) { header.tap() }
        XCTAssertTrue(clients.waitForExistence(timeout: 5))

        header.tap()
        XCTAssertTrue(clients.waitForNonExistence(timeout: 5), "one click folds the section")
        attach(app, "sidebar-folded")

        app.terminate()
        app = launch()
        let sidebarAgain = app.collectionViews["mailboxes"]
        let headerAgain = sidebarAgain.cells["section.account.synthetic-2"]
        XCTAssertTrue(sidebarAgain.waitForExistence(timeout: 5))
        XCTAssertTrue(scroll(sidebarAgain, toReveal: headerAgain))
        XCTAssertFalse(
            scroll(sidebarAgain, toReveal: sidebarAgain.cells["mailbox.Label_3.synthetic-2"]), "still folded")

        headerAgain.tap()
        XCTAssertTrue(
            scroll(sidebarAgain, toReveal: sidebarAgain.cells["mailbox.Label_3.synthetic-2"]), "one click unfolds it")
        attach(app, "sidebar-unfolded")
    }

    /// Swipes the sidebar up until `element` is on show, a few times at most. Returns whether it is.
    @MainActor
    @discardableResult
    private func scroll(_ sidebar: XCUIElement, toReveal element: XCUIElement) -> Bool {
        // Rows unfolding animate in.
        if element.waitForExistence(timeout: 2) { return true }
        for _ in 0..<4 where !element.exists { sidebar.swipeUp() }
        return element.exists
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GoodmailSyntheticThreads", "200", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments += AnimationSpeed.fast.arguments
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
