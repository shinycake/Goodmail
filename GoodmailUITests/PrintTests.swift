import XCTest

/// The reader's Share menu offers the conversation as a PDF, plain text, `.eml` files and an `.mbox` archive, and
/// Print, in English and in Hebrew. Nothing is printed or sent: the sheets are only opened. Synthetic mailboxes
/// have no provider to fetch raw sources from, so `.eml` and `.mbox` are only checked to be on offer.
final class PrintTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheShareMenuSharesAConversationAsAPDFInEnglish() {
        let app = launch(language: "en", locale: "en_US")
        open("Review → Thursday?", in: app)
        openShareMenu(in: app)
        XCTAssertTrue(app.buttons["Print…"].waitForExistence(timeout: 5), "the Share menu offers Print")
        for format in ["PDF", "Plain Text", "Email File (.eml)", "Mailbox Archive (.mbox)"] {
            XCTAssertTrue(app.buttons[format].exists, "the Share menu offers \(format)")
        }
        attach(app, "share-menu-en")
        app.buttons["PDF"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the share sheet opens")
        // The caption fills in a moment after the sheet appears, so wait for it rather than reading it once.
        let caption = sheet.otherElements["LP.CaptionBar.BottomCaption"]
        let offersPDF = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH 'PDF Document'"), object: caption)
        XCTAssertEqual(XCTWaiter.wait(for: [offersPDF], timeout: 10), .completed, "the share sheet offers the PDF")
        attach(app, "print-share-en")
    }

    @MainActor
    func testTheShareMenuSharesAConversationAsTextInEnglish() {
        let app = launch(language: "en", locale: "en_US")
        open("Review → Thursday?", in: app)
        openShareMenu(in: app)
        app.buttons["Plain Text"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the share sheet opens")
        attach(app, "share-text-en")
    }

    @MainActor
    func testTheShareMenuPrintsAConversationInEnglish() {
        let app = launch(language: "en", locale: "en_US")
        open("Review → Thursday?", in: app)
        openShareMenu(in: app)
        app.buttons["Print…"].tap()
        XCTAssertTrue(app.buttons["Print"].waitForExistence(timeout: 30), "the print options open")
        attach(app, "print-preview-en")
    }

    @MainActor
    func testTheShareMenuOffersEveryFormatInHebrew() {
        let app = launch(language: "he", locale: "he_IL")
        open("Review → Thursday?", in: app)
        openShareMenu(in: app)
        XCTAssertTrue(app.buttons["הדפסה…"].waitForExistence(timeout: 5))
        for format in ["PDF", "טקסט פשוט", "קובץ דוא״ל (\u{200E}.eml)", "ארכיון תיבת דואר (\u{200E}.mbox)"] {
            XCTAssertTrue(app.buttons[format].exists, "the Share menu offers \(format)")
        }
        attach(app, "share-menu-he")
    }

    /// On a phone the Share button folds into the toolbar's More menu, as a top-level submenu.
    @MainActor
    private func openShareMenu(in app: XCUIApplication) {
        let more = app.buttons["BottomOverflowBarButtonItem"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let share = app.buttons.matching(NSPredicate(format: "label == 'Share' OR label == 'שיתוף'")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5), "More holds the Share menu")
        attach(app, "more-menu")
        share.tap()
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
