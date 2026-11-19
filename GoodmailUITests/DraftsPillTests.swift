import XCTest

/// Minimizing the composer puts it in the drafts pill at the leading end of the list's toolbar, without moving
/// Compose; tapping the pill brings it back, or lays several out to pick one. Search lives in the navigation bar.
final class DraftsPillTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMinimizingShowsThePillAndLeavesComposeInPlace() {
        let app = launch()
        let compose = app.toolbars.buttons["New Message"]
        let before = compose.frame
        write("Lunch", in: app)
        minimize(app)
        let pill = app.toolbars.buttons["drafts.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the pill shows")
        XCTAssertEqual(pill.label, "1 Draft")
        XCTAssertEqual(compose.frame, before, "Compose stays where it was")
        attach(app, "pill-one")
    }

    @MainActor
    func testTappingTheOnlyDraftOpensIt() {
        let app = launch()
        write("Lunch", in: app)
        minimize(app)
        let pill = app.toolbars.buttons["drafts.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.tap()
        let subject = app.textFields["compose.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5), "the message opens")
        XCTAssertEqual(subject.value as? String, "Lunch")
        XCTAssertFalse(app.toolbars.buttons["drafts.pill"].exists, "the pill is gone while it's written")
    }

    @MainActor
    func testSeveralDraftsArePickedFrom() {
        let app = launch()
        write("Lunch", in: app)
        minimize(app)
        write("Budget", in: app)
        minimize(app)
        let pill = app.toolbars.buttons["drafts.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "2 Drafts")
        pill.tap()
        let cards = app.otherElements.matching(identifier: "drafts.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5), "the drafts are laid out")
        XCTAssertEqual(cards.count, 2)
        app.buttons["Lunch"].firstMatch.tap()
        let subject = app.textFields["compose.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        XCTAssertEqual(subject.value as? String, "Lunch")
        minimize(app)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "2 Drafts", "both wait again")
        pill.tap()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Budget"].firstMatch.tap()
        XCTAssertTrue(subject.waitForExistence(timeout: 5))
        XCTAssertEqual(subject.value as? String, "Budget")
    }

    @MainActor
    func testSelectingHidesThePillUntilDone() {
        let app = launch()
        write("Lunch", in: app)
        minimize(app)
        let pill = app.toolbars.buttons["drafts.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Select"].tap()
        XCTAssertTrue(app.toolbars.buttons["Archive"].waitForExistence(timeout: 5))
        XCTAssertFalse(pill.exists, "selecting swaps the pill out with Compose")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Done brings it back")
        XCTAssertEqual(pill.label, "1 Draft")
    }

    @MainActor
    func testAThreadHasNoPillAndTheListGetsItBack() {
        let app = launch()
        // The first cell is the first section's header.
        let row = app.collectionViews["mailbox"].cells.element(boundBy: 1)
        row.tap()
        let thread = app.scrollViews["thread"]
        if !thread.waitForExistence(timeout: 5) { row.tap() }
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "the thread opens")
        app.toolbars.buttons["Reply"].tap()
        let body = app.textViews["compose.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("Sounds good")
        minimize(app)
        XCTAssertFalse(app.toolbars.buttons["drafts.pill"].waitForExistence(timeout: 2), "a thread has no pill")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let pill = app.toolbars.buttons["drafts.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the list has it")
        XCTAssertEqual(pill.label, "1 Draft")
    }

    @MainActor
    func testAnEmptyMessagePulledDownLeavesNoPill() {
        let app = launch()
        app.toolbars.buttons["New Message"].tap()
        XCTAssertTrue(app.textFields["compose.subject"].waitForExistence(timeout: 5))
        minimize(app)
        XCTAssertFalse(app.textFields["compose.subject"].waitForExistence(timeout: 2), "the message is gone")
        XCTAssertFalse(app.toolbars.buttons["drafts.pill"].exists, "nothing waits")
    }

    @MainActor
    func testSearchIsInTheNavigationBar() {
        let app = launch()
        XCTAssertFalse(app.toolbars.buttons["Search"].exists, "the toolbar has no search")
        let search = app.navigationBars.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "search is at the top")
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertLessThan(field.frame.midY, app.frame.midY, "the field opens in the top half")
    }

    @MainActor
    func testSearchOpensAndClosesLeavingTheBarAsItWas() {
        let app = launch()
        let bar = app.navigationBars.firstMatch
        let buttons = [bar.buttons["Select"], bar.buttons["Search"], bar.buttons["mailboxesSidebar"]]
        XCTAssertTrue(buttons[0].waitForExistence(timeout: 5))
        let before = buttons.map(\.frame)
        buttons[1].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "the field opens")
        app.buttons["close"].firstMatch.tap()
        XCTAssertTrue(buttons[0].waitForExistence(timeout: 5), "the bar comes back")
        XCTAssertEqual(buttons.map(\.frame), before, "Select, Search and the sidebar button are where they were")
    }

    @MainActor
    func testMinimizingInHebrew() {
        let app = launch(language: "he", locale: "he_IL")
        write("ארוחת צהריים", in: app, compose: "הודעה חדשה")
        minimize(app)
        XCTAssertTrue(app.toolbars.buttons["drafts.pill"].waitForExistence(timeout: 5))
        attach(app, "pill-hebrew")
    }

    /// Starts a message from Compose, titled `compose` in the app's language, with `subject`.
    @MainActor
    private func write(_ subject: String, in app: XCUIApplication, compose: String = "New Message") {
        app.toolbars.buttons[compose].tap()
        let field = app.textFields["compose.subject"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the composer opens")
        field.tap()
        field.typeText(subject)
    }

    /// Pulls the composer's card down by its navigation bar to the bottom of the screen.
    @MainActor
    private func minimize(_ app: XCUIApplication) {
        let bar = app.navigationBars.element(boundBy: app.navigationBars.count - 1)
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func launch(language: String = "en", locale: String = "en_US") -> XCUIApplication {
        // The test-mail corpus files whole threads, bodies included, so Reply has a message to answer.
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-GoodmailSyntheticArrivalEvery",
            "3600", "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
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
