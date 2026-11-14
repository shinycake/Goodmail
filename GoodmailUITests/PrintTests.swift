import XCTest

/// The reader's Reply menu offers Print and Share as PDF, in English and in Hebrew, and a PDF lays out the
/// conversation. Nothing is printed or sent: the sheets are only opened.
final class PrintTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheReplyMenuSharesAConversationAsAPDFInEnglish() {
        let app = launch(language: "en", locale: "en_US")
        open("Review → Thursday?", in: app)
        openReplyMenu(in: app)
        XCTAssertTrue(app.buttons["Print…"].waitForExistence(timeout: 5), "the Reply menu offers Print")
        XCTAssertTrue(app.buttons["Share as PDF…"].exists, "the Reply menu offers Share as PDF")
        attach(app, "print-menu-en")
        app.buttons["Share as PDF…"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the share sheet opens")
        XCTAssertTrue(
            sheet.otherElements["LP.CaptionBar.BottomCaption"].label.hasPrefix("PDF Document"),
            "the share sheet offers the PDF")
        attach(app, "print-share-en")
    }

    @MainActor
    func testTheReplyMenuPrintsAConversationInEnglish() {
        let app = launch(language: "en", locale: "en_US")
        open("Review → Thursday?", in: app)
        openReplyMenu(in: app)
        app.buttons["Print…"].tap()
        XCTAssertTrue(app.buttons["Print"].waitForExistence(timeout: 30), "the print options open")
        attach(app, "print-preview-en")
    }

    @MainActor
    func testTheReplyMenuOffersPrintInHebrew() {
        let app = launch(language: "he", locale: "he_IL")
        open("Review → Thursday?", in: app)
        openReplyMenu(in: app)
        XCTAssertTrue(app.buttons["הדפסה…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["שיתוף כ־PDF…"].exists)
        attach(app, "print-menu-he")
    }

    /// On a phone the Reply button folds into the toolbar's More menu, as a submenu holding the Reply menu.
    @MainActor
    private func openReplyMenu(in app: XCUIApplication) {
        let more = app.buttons["BottomOverflowBarButtonItem"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let reply = app.buttons.matching(NSPredicate(format: "label == 'Reply' OR label == 'השב'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "More holds the Reply menu")
        reply.tap()
    }

    @MainActor
    private func open(_ subject: String, in app: XCUIApplication) {
        let row = app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", subject))
            .firstMatch
        // The list only builds the cells on screen: scroll the thread into view when it sits below the fold.
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.collectionViews["mailbox"].swipeUp(velocity: .slow) }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(
            row.wait(for: \.isHittable, toEqual: true, timeout: 10), "the row is on screen and takes touches")
        let thread = app.scrollViews["thread"]
        row.tap()
        // As in ChatLayoutTests: a first tap during the launch transition can be dropped on a busy Mac.
        if !thread.waitForExistence(timeout: 5) { row.tap() }
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "the thread opens")
    }

    @MainActor
    private func launch(language: String, locale: String) -> XCUIApplication {
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-conversationLayout", "classic",
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
