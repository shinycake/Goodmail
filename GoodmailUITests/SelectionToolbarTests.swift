import XCTest

/// Selecting threads fills the toolbar with what can be done to them, in every kind of list, and what takes them out
/// of the way stays in the toolbar rather than folding into More. Reading a thread and coming back leaves the list's
/// toolbar in place.
final class SelectionToolbarTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSelectingInTheInboxOffersArchiveAndTrash() {
        let app = launch()
        assertSelectingOffers(["Archive", "Trash"], in: app, "unified-inbox")
    }

    @MainActor
    func testSelectingInALabelOffersTrash() {
        let app = launch()
        open("mailbox.Label_1.synthetic-1", in: app)
        assertSelectingOffers(["Trash"], in: app, "label")
    }

    @MainActor
    func testSelectingInSentOffersTrash() {
        let app = launch()
        open("mailbox.SENT", in: app)
        assertSelectingOffers(["Trash"], in: app, "sent")
    }

    @MainActor
    func testSelectingInTrashOffersMoveOutAndDeleteForever() {
        let app = launch()
        open("mailbox.TRASH", in: app)
        assertSelectingOffers(["Move Out of Trash", "Delete Forever"], in: app, "trash")
    }

    /// A chat reader hides the toolbar for its composer. Going back, the list's Search, New Message and selection
    /// actions are there again, even when the thread changes while the reader leaves.
    @MainActor
    func testComingBackFromAChatKeepsTheListsToolbar() {
        let app = launch(corpus: true)
        for _ in 0..<3 {
            // The first cell is the first section's header.
            let row = app.collectionViews["mailbox"].cells.element(boundBy: 1)
            row.tap()
            let thread = app.scrollViews["thread"]
            if !thread.waitForExistence(timeout: 5) { row.tap() }
            XCTAssertTrue(thread.waitForExistence(timeout: 10), "the thread opens")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.collectionViews["mailbox"].waitForExistence(timeout: 5))
            XCTAssertTrue(
                app.toolbars.buttons["New Message"].waitForExistence(timeout: 5), "the list's toolbar is back")
        }
        assertSelectingOffers(["Archive", "Trash"], in: app, "after-chat")
    }

    @MainActor
    private func assertSelectingOffers(
        _ titles: [String], in app: XCUIApplication, _ name: String, line: UInt = #line
    ) {
        app.navigationBars.buttons["Select"].tap()
        // The actions show from the start, disabled until a row is picked, so the toolbar doesn't jump.
        let first = app.toolbars.buttons[titles[0]]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "selecting shows the actions, not in More", line: line)
        XCTAssertFalse(first.isEnabled, "nothing to act on before a row is picked", line: line)
        // The first cell is the first section's header.
        app.collectionViews["mailbox"].cells.element(boundBy: 1).tap()
        XCTAssertTrue(
            app.navigationBars["1 Selected"].waitForExistence(timeout: 5), "the row is selected", line: line)
        for title in titles {
            let button = app.toolbars.buttons[title]
            XCTAssertTrue(button.exists, "\(title) is in the toolbar, not in More", line: line)
            XCTAssertTrue(button.isEnabled, "\(title) acts on the selection", line: line)
        }
        attach(app, "select-\(name)")
    }

    /// Opens a mailbox from the mailboxes behind the list.
    @MainActor
    private func open(_ identifier: String, in app: XCUIApplication) {
        let cell = app.collectionViews["mailboxes"].cells[identifier].firstMatch
        // On a phone the mailboxes are behind the list; on iPad the sidebar already shows them.
        if !cell.isHittable { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
    }

    /// The synthetic mailboxes, seeded fresh each launch, or with `corpus` the test-mail corpus read as chats.
    @MainActor
    private func launch(corpus: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "40", "-GoodmailSyntheticArrivalEvery", "3600",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        if corpus {
            let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "TestMail").path(percentEncoded: false)
            app.launchArguments += ["-GoodmailSyntheticCorpus", folder, "-conversationLayout", "chat"]
        }
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
