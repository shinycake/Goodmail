import XCTest

/// Settings stays open while the reader moves around in it, even after changing something; only closing it brings
/// the mail screens back.
final class SettingsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOpeningAnAccountAfterAChangeKeepsSettingsOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["-GoodmailSyntheticThreads", "200", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        if app.windows.firstMatch.horizontalSizeClass == .compact {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.buttons["Settings"].firstMatch.tap()
        let settings = app.navigationBars["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        // A change counts only once Settings closes, so the mail screens are rebuilt then and not before.
        // The row is a switch holding the switch itself; tapping the row's label doesn't flip it.
        let avatars = app.switches["Avatars"].switches.firstMatch
        let before = avatars.value as? String
        avatars.tap()
        XCTAssertNotEqual(avatars.value as? String, before)
        // A button only in Settings: the mailboxes behind the sheet list the account as a cell.
        app.buttons["you@example.com"].tap()
        let account = app.navigationBars["you@example.com"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        XCTAssertFalse(
            account.waitForNonExistence(timeout: 2), "opening an account after a change must not close Settings")

        account.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertFalse(settings.waitForNonExistence(timeout: 2), "going back to Settings must not close it")

        settings.buttons["Close"].tap()
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.collectionViews["mailbox"].waitForExistence(timeout: 5), "closing Settings shows the mail")
    }
}
