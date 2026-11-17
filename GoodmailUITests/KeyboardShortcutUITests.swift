import XCTest

/// A hardware keyboard, or Full Keyboard Access, reaches the main commands without touching the screen.
final class KeyboardShortcutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCommandNStartsAMessage() {
        let app = launch()
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["compose.to"].waitForExistence(timeout: 5), "⌘N opens the composer")
    }

    @MainActor
    func testAThreadAnswersAndArchivesFromTheKeyboard() {
        let app = launch()
        let list = app.collectionViews["mailbox"]
        list.cells.containing(NSPredicate(format: "label CONTAINS 'Saturday?'")).firstMatch.tap()
        let thread = app.scrollViews["thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 5))

        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(app.textFields["compose.to"].waitForExistence(timeout: 5), "⌘R replies")
        app.buttons["compose.close"].tap()
        XCTAssertTrue(app.textFields["compose.to"].waitForNonExistence(timeout: 5))

        app.typeKey("a", modifierFlags: [.command, .control])
        XCTAssertTrue(
            app.staticTexts["Archived"].waitForExistence(timeout: 5), "⌃⌘A archives and confirms with a toast")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "keyboard-archive"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        // The test-mail corpus files whole threads, so Reply has a message to answer.
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        return app
    }
}
