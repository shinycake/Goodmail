import XCTest

/// Launches the app in each shipping language and attaches a screenshot as PR evidence.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesInEnglish() {
        launch(language: "en", locale: "en_US", expecting: "Fast, simple mail. Add an account to get started.")
    }

    @MainActor
    func testLaunchesInHebrew() {
        launch(language: "he", locale: "he_IL", expecting: "דואר מהיר ופשוט. כדי להתחיל, מוסיפים חשבון.")
    }

    /// iOS runs background app refresh on a background queue; a refresh that needs the main actor traps there, as
    /// build 1.0 (1) did on TestFlight.
    @MainActor
    func testBackgroundRefreshRunsOffTheMainActor() {
        let app = XCUIApplication()
        app.launchArguments = ["-GoodmailRunBackgroundRefresh", "YES"]
        app.launch()
        XCTAssertFalse(app.wait(for: .notRunning, timeout: 5), "the app crashed running background refresh")
    }

    @discardableResult @MainActor
    private func launch(language: String, locale: String, expecting text: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "launch-\(language)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        return app
    }
}
