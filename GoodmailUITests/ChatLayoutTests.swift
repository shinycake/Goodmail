import XCTest

/// The chat layout reads the test-mail corpus as bubbles, in English and in Hebrew, and attaches what it saw.
final class ChatLayoutTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAOneToOneThreadReadsAsBubblesInEnglish() {
        let app = launch(language: "en", locale: "en_US")
        open("Saturday?", in: app)
        XCTAssertTrue(
            app.otherElements.containing(NSPredicate(format: "label CONTAINS 'Yes to both! 10 works.'"))
                .firstMatch.waitForExistence(timeout: 5), "my reply shows without its quote or iPhone signature")
        attach(app, "chat-en")
        app.buttons["Mail Actions"].tap()
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5), "the tray unfolds the mail actions")
        attach(app, "chat-en-actions")
    }

    @MainActor
    func testAGroupThreadReadsAsBubblesInHebrew() {
        let app = launch(language: "he", locale: "he_IL")
        open("ארוחת שישי", in: app)
        XCTAssertTrue(
            app.otherElements.containing(NSPredicate(format: "label CONTAINS 'אני בפנים! אביא חלה.'"))
                .firstMatch.waitForExistence(timeout: 5))
        attach(app, "chat-he")
        app.textViews["הודעה"].tap()
        app.typeText("נתראה בשישי!")
        attach(app, "chat-he-typing")
        let send = app.buttons.matching(identifier: "chat.send").firstMatch
        XCTAssertTrue(send.isEnabled, "typed words can go")
    }

    @MainActor
    private func open(_ subject: String, in app: XCUIApplication) {
        let row = app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", subject))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(
            row.wait(for: \.isHittable, toEqual: true, timeout: 10), "the row is on screen and takes touches")
        let thread = app.scrollViews["thread"]
        row.tap()
        // On a busy Mac running the whole check, the first tap can land while the app is still finishing its launch
        // transition and be dropped, with the list showing and nothing opened. One more tap opens it then.
        if !thread.waitForExistence(timeout: 5) { row.tap() }
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "the thread opens")
    }

    @MainActor
    private func launch(language: String, locale: String) -> XCUIApplication {
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-conversationLayout", "chat",
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
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
