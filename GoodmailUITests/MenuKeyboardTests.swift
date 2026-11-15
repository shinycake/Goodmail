import XCTest

/// Opening a menu shows the menu and nothing else: no screen holds first responder, so the keyboard stays down.
final class MenuKeyboardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheInboxCategoryMenuOpensWithoutTheKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))

        let category = app.buttons["inboxCategory"]
        XCTAssertTrue(category.wait(for: \.isHittable, toEqual: true, timeout: 10), "the Inbox offers its categories")
        category.tap()
        // Each category reads with its unread count, "Social, 1 unread".
        let social = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Social'")).firstMatch
        XCTAssertTrue(social.waitForExistence(timeout: 5), "the category menu opened")
        // The keyboard rose a beat after the menu, so give it the time it took before saying it stayed down.
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2), "no keyboard rises with the menu")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "category-menu-no-keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
