import XCTest

/// The journeys every change must keep working, short enough for `scripts/check` to run on each push: the list shows,
/// a conversation opens and goes back, a swipe archives and Undo brings it back, Compose opens and closes, Settings
/// opens and closes, and the same conversation round trip in Hebrew. The full suite (`scripts/ui-suite`) goes deeper.
final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAConversationOpensAndGoesBack() {
        let app = XCUIApplication.launchedOnSyntheticMail(animations: .fast)
        openAndGoBack(in: app)
    }

    @MainActor
    func testAConversationOpensAndGoesBackInHebrew() {
        let app = XCUIApplication.launchedOnSyntheticMail(language: .hebrew, animations: .fast)
        openAndGoBack(in: app)
    }

    @MainActor
    func testSwipingArchivesAndUndoBringsItBack() {
        let app = XCUIApplication.launchedOnSyntheticMail(animations: .fast)
        let first = app.subjects(ofFirst: 2)
        let archive = app.buttons["Archive"]
        XCTAssertTrue(app.row(showing: first[0]).swipeOpen(showing: archive), "the swipe shows Archive")
        archive.tap()
        XCTAssertTrue(waitUntil { topSubject(in: app) == first[1] }, "the archived row leaves the list")

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the toast offers Undo")
        undo.tap()
        XCTAssertTrue(waitUntil { topSubject(in: app) == first[0] }, "Undo puts the row back on top")
    }

    @MainActor
    func testComposeOpensAndCloses() {
        let app = XCUIApplication.launchedOnSyntheticMail(animations: .fast)
        app.toolbars.buttons["New Message"].tap()
        let subject = app.textFields["compose.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5), "the composer opens")
        app.buttons["compose.close"].tap()
        XCTAssertTrue(subject.waitForNonExistence(timeout: 5), "closing an empty message puts it away")
        XCTAssertTrue(app.toolbars.buttons["New Message"].isHittable, "the list is back")
    }

    @MainActor
    func testSettingsOpensAndCloses() {
        let app = XCUIApplication.launchedOnSyntheticMail(animations: .fast)
        // A phone keeps Settings in the mailboxes behind the list.
        if app.windows.firstMatch.horizontalSizeClass == .compact {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.buttons["Settings"].firstMatch.tap()
        let settings = app.navigationBars["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings opens")
        settings.buttons["Close"].tap()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5), "Settings closes")
    }

    // MARK: Helpers

    /// Opens the top conversation, checks the reader shows it, and goes back to the list.
    @MainActor
    private func openAndGoBack(in app: XCUIApplication) {
        let subject = app.subjects(ofFirst: 1)[0]
        let reader = app.scrollViews["thread"]
        XCTAssertTrue(
            retry({ app.row(showing: subject).tap() }, until: { reader.exists }), "the conversation opens")
        let shown = app.staticTexts["thread.subject"]
        XCTAssertTrue(waitUntil { shown.exists && shown.label == subject }, "the reader shows the tapped conversation")
        guard app.windows.firstMatch.horizontalSizeClass == .compact else { return }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(reader.waitForNonExistence(timeout: 5), "Back goes to the list")
        XCTAssertTrue(app.collectionViews["mailbox"].isHittable, "the list shows")
    }

    /// The subject of the list's top conversation right now, if it shows one.
    @MainActor
    private func topSubject(in app: XCUIApplication) -> String? {
        (try? app.collectionViews["mailbox"].snapshot()).flatMap { SyntheticMail.rowSubjects(in: $0).first }
    }
}
