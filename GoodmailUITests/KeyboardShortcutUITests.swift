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

    /// ⌃⌘↓ and ⌃⌘↑ read the conversation below and above, beside the list and in a narrow stack whose reader covers
    /// it.
    @MainActor
    func testNextAndPreviousConversationFromTheKeyboard() {
        let app = launch()
        let first = openFirstConversation(in: app)
        app.typeKey(.downArrow, modifierFlags: [.command, .control])
        XCTAssertTrue(waitUntil { subject(in: app) != first }, "⌃⌘↓ reads the conversation below")
        app.typeKey(.upArrow, modifierFlags: [.command, .control])
        XCTAssertTrue(waitUntil { subject(in: app) == first }, "⌃⌘↑ goes back up")
        app.typeKey(.upArrow, modifierFlags: [.command, .control])
        XCTAssertEqual(subject(in: app), first, "nothing is above the first row")
    }

    /// On iPhone, the reader's bar has the chevrons Mail has, named for VoiceOver, the one above dimmed at the top,
    /// pointing up and down in English and in Hebrew.
    @MainActor
    func testTheReadersChevronsStepThroughTheList() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "a pushed reader is iPhone's")
        for (language, next, previous) in [
            ("en", "Next Conversation", "Previous Conversation"), ("he", "השיחה הבאה", "השיחה הקודמת"),
        ] {
            let app = launch(language: language)
            let first = openFirstConversation(in: app)
            let up = app.navigationBars.buttons["thread.previous"]
            let down = app.navigationBars.buttons["thread.next"]
            XCTAssertTrue(down.waitForExistence(timeout: 5))
            XCTAssertEqual(down.label, next)
            XCTAssertEqual(up.label, previous)
            XCTAssertFalse(up.isEnabled, "dimmed at the top of the list")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "reader-chevrons-\(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            down.tap()
            XCTAssertTrue(waitUntil { subject(in: app) != first }, "the one below is read")
            XCTAssertTrue(waitUntil { up.isEnabled })
            up.tap()
            XCTAssertTrue(waitUntil { subject(in: app) == first }, "and the one above again")
            app.terminate()
        }
    }

    /// Opens the first row's conversation and returns its subject.
    @MainActor
    private func openFirstConversation(in app: XCUIApplication) -> String {
        // The list's first cell is its section's header; a conversation's row names the account it's in.
        let row = app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS '@example.com'"))
            .firstMatch
        XCTAssertTrue(retry({ row.tap() }, until: { app.scrollViews["thread"].exists }), "the conversation opens")
        let shown = app.staticTexts["thread.subject"]
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        return shown.label
    }

    @MainActor
    private func subject(in app: XCUIApplication) -> String {
        app.staticTexts["thread.subject"].label
    }

    @MainActor
    private func launch(language: String = "en") -> XCUIApplication {
        // The test-mail corpus files whole threads, so Reply has a message to answer.
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "he" ? "he_IL" : "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        return app
    }
}
