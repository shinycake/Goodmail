import XCTest

/// Touching and holding the app icon offers the main ways into the mail, and each goes where it says.
final class QuickActionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testUnreadOpensSearchWithItsFilter() {
        let app = launch(language: "en")
        choose("Unread", in: app)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "Unread opens search")
        let token = app.searchFields.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Unread'")).firstMatch
        XCTAssertTrue(token.waitForExistence(timeout: 5), "with its Unread filter as a token")
        keep(app, "quick-action-unread")
    }

    @MainActor
    func testNewMessageOpensTheComposer() {
        let app = launch(language: "en")
        choose("New Message", in: app)
        XCTAssertTrue(app.textFields["compose.to"].waitForExistence(timeout: 5), "New Message opens the composer")
    }

    @MainActor
    func testSearchIsReadyToType() {
        let app = launch(language: "he")
        choose("חיפוש", in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Search raises the keyboard")
        keep(app, "quick-action-search-he")
    }

    @MainActor
    func testSearchMinimizesTheMessageBeingWritten() {
        let app = launch(language: "en")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["compose.to"].waitForExistence(timeout: 5))
        choose("Unread", in: app)
        XCTAssertTrue(app.textFields["compose.to"].waitForNonExistence(timeout: 5), "The message goes to the bar")
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "and search opens over the list")
        keep(app, "quick-action-search-over-composer")
    }

    /// Leaves the app for the Home Screen, which sets the menu, then touches and holds its icon and picks `title`.
    @MainActor
    private func choose(_ title: String, in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // A new simulator asks to allow notifications on the first launch, and the Home button can't get past the
        // alert. Its second button allows them, in any language.
        let permission = springboard.alerts.firstMatch
        if permission.waitForExistence(timeout: 2) { permission.buttons.element(boundBy: 1).tap() }
        XCUIDevice.shared.press(.home)
        let icon = springboard.icons["Goodmail"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        icon.press(forDuration: 1.2)
        let action = springboard.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "The menu offers \(title)")
        keep(springboard, "quick-action-menu-\(app.launchArguments.contains("(he)") ? "he" : "en")")
        action.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    private func keep(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func launch(language: String) -> XCUIApplication {
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "he" ? "he_IL" : "en_US",
        ]
        app.launchArguments += AnimationSpeed.fast.arguments
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        return app
    }
}
