import XCTest

/// Touching and holding a row lifts its preview and offers the thread's actions, in the reader's language.
final class ContextMenuTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testHoldingARowOffersAnswersAndActionsWithTrashLast() {
        let app = launch(language: "en", locale: "en_US")
        thread("Saturday?", in: app).press(forDuration: 1.2)
        for title in ["Reply", "Reply All", "Forward", "Move to…", "Archive", "Trash"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), "\(title) is in the menu")
        }
        XCTAssertLessThan(app.buttons["Reply"].frame.minY, app.buttons["Trash"].frame.minY, "Trash comes last")
        attach(app, "context-menu-en")

        app.buttons["Reply"].tap()
        let subject = app.textFields["compose.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 10), "the composer opened")
        XCTAssertEqual(subject.value as? String, "Re: Saturday?", "answering the thread's newest message")
        attach(app, "context-menu-reply")
    }

    @MainActor
    func testTheMenuReadsInHebrew() {
        let app = launch(language: "he", locale: "he_IL")
        thread("ארוחת שישי", in: app).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["השב"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["העבר"].exists)
        attach(app, "context-menu-he")
    }

    @MainActor
    private func launch(language: String, locale: String) -> XCUIApplication {
        // The test-mail corpus files whole threads, bodies included, so Reply has a message to answer.
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        app.launchArguments += AnimationSpeed.fast.arguments
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    /// The row of the thread about `subject`, once it is on screen and takes touches.
    @MainActor
    private func thread(_ subject: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", subject))
            .firstMatch
        XCTAssertTrue(row.wait(for: \.isHittable, toEqual: true, timeout: 10), "the row is on screen")
        return row
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
