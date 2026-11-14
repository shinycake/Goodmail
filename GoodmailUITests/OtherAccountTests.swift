import XCTest

/// The Other Mail Account form keeps the typed password from the account step to the server step, in each shipping
/// language. The address is on a domain no lookup knows, so the form always moves on to the servers.
final class OtherAccountTests: XCTestCase {
    private let password = "secret-pass"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testThePasswordCarriesOverToTheServersInEnglish() {
        checkPasswordCarriesOver(language: "en", locale: "en_US")
    }

    @MainActor
    func testThePasswordCarriesOverToTheServersInHebrew() {
        checkPasswordCarriesOver(language: "he", locale: "he_IL")
    }

    @MainActor
    private func checkPasswordCarriesOver(language: String, locale: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()

        let other = app.buttons["addAccount.imap"]
        XCTAssertTrue(other.waitForExistence(timeout: 10), "the welcome screen offers Other Mail Account")
        other.tap()

        let name = app.textFields["other-account-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Dana Levi")
        let email = app.textFields["other-account-email"]
        email.tap()
        email.typeText("dana@nonexistent-goodmail-test.example")
        let passwordField = app.secureTextFields["other-account-password"]
        passwordField.tap()
        passwordField.typeText(password)
        XCTAssertEqual(dots(in: passwordField), password.count, "the account step shows every typed character")

        app.buttons["other-account-submit"].tap()
        XCTAssertTrue(
            app.textFields["other-account-host"].firstMatch.waitForExistence(timeout: 30),
            "the form asks for the servers when the lookup finds none")
        XCTAssertEqual(dots(in: passwordField), password.count, "the password carries over to the server step")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "other-account-servers-\(language)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// How many characters the secure field holds, from the dots it reports.
    @MainActor
    private func dots(in field: XCUIElement) -> Int {
        (field.value as? String ?? "").filter { $0 == "•" }.count
    }
}
