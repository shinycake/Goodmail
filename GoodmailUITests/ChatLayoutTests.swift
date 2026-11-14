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
    }

    @MainActor
    func testAGroupThreadReadsAsBubblesInHebrew() {
        let app = launch(language: "he", locale: "he_IL")
        open("ארוחת שישי", in: app)
        XCTAssertTrue(
            app.otherElements.containing(NSPredicate(format: "label CONTAINS 'אני בפנים! אביא חלה.'"))
                .firstMatch.waitForExistence(timeout: 5))
        attach(app, "chat-he")
    }

    @MainActor
    private func open(_ subject: String, in app: XCUIApplication) {
        let row = app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", subject))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.scrollViews["thread"].waitForExistence(timeout: 5))
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
