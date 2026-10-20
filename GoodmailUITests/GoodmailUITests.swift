import XCTest

/// Launches the app in each shipping language and attaches a screenshot as PR evidence.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesInEnglish() {
        launch(language: "en", locale: "en_US", expecting: "No Accounts")
    }

    @MainActor
    func testLaunchesInHebrew() {
        launch(language: "he", locale: "he_IL", expecting: "אין חשבונות")
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
