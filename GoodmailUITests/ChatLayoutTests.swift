import XCTest

/// The chat layout reads the test-mail corpus as bubbles, in English and in Hebrew, and attaches what it saw.
final class ChatLayoutTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAOneToOneThreadReadsAsBubblesInEnglish() {
        let app = launch(language: "en", locale: "en_US")
        open("Saturday?", in: app)
        XCTAssertTrue(
            app.otherElements.containing(NSPredicate(format: "label CONTAINS 'Yes to both! 10 works.'"))
                .firstMatch.waitForExistence(timeout: 5), "my reply shows without its quote or iPhone signature")
        attach(app, "chat-en")
        app.buttons["Mail Actions"].tap()
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5), "the tray unfolds the mail actions")
        attach(app, "chat-en-actions")
    }

    @MainActor
    func testAGroupThreadReadsAsBubblesInHebrew() {
        let app = launch(language: "he", locale: "he_IL")
        open("ארוחת שישי", in: app)
        XCTAssertTrue(
            app.otherElements.containing(NSPredicate(format: "label CONTAINS 'אני בפנים! אביא חלה.'"))
                .firstMatch.waitForExistence(timeout: 5))
        attach(app, "chat-he")
        app.textViews["הודעה"].tap()
        app.typeText("נתראה בשישי!")
        attach(app, "chat-he-typing")
        let send = app.buttons.matching(identifier: "chat.send").firstMatch
        XCTAssertTrue(send.isEnabled, "typed words can go")
    }

    @MainActor
    func testALaidOutLetterOpensInFull() {
        let app = launch(language: "en", locale: "en_US")
        open("This week at Example Co", in: app)
        let letter = app.buttons["chat.letter"].firstMatch
        XCTAssertTrue(letter.waitForExistence(timeout: 5), "a newsletter reads as a letter bubble")
        attach(app, "chat-letter")
        letter.tap()
        XCTAssertTrue(
            app.links["Read more"].waitForExistence(timeout: 20), "tapping the letter opens it in full, body and all")
        attach(app, "chat-letter-open")
    }

    /// A reader pushed on an iPhone's stack keeps room in its bar for the chat's title beside its own capsule of up and
    /// down chevrons and the layout switch, at the default text size and the largest, in English and in Hebrew. The
    /// screenshots are for checking a 375-point-wide phone by eye.
    @MainActor
    func testThePushedChatReadersBarHasRoomForItsTitle() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "a pushed reader is iPhone's")
        for (language, locale, subject) in [("en", "en_US", "Saturday?"), ("he", "he_IL", "ארוחת שישי")] {
            for size in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
                let app = launch(language: language, locale: locale, size: size)
                open(subject, in: app)
                let bar = app.navigationBars.firstMatch
                let down = bar.buttons["thread.next"]
                let up = bar.buttons["thread.previous"]
                XCTAssertTrue(down.waitForExistence(timeout: 5))
                XCTAssertFalse(down.frame.intersects(up.frame), "up and down are two buttons")
                let back = bar.buttons.element(boundBy: 0)
                XCTAssertFalse(back.frame.intersects(up.frame), "the chevrons leave Back its room")
                attach(app, "chat-bar-\(language)-\(size == nil ? "default" : "ax5")")
                app.terminate()
            }
        }
    }

    @MainActor
    private func open(_ subject: String, in app: XCUIApplication) {
        let row = app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", subject))
            .firstMatch
        let list = app.collectionViews["mailbox"]
        // Rows below the screen aren't laid out yet, so scroll until the row is there and clear of the toolbar
        // along the bottom, which takes a tap at the row's middle when it sits under it.
        for _ in 0..<12 {
            if !row.exists || row.frame.maxY > list.frame.maxY - 120 {
                list.swipeUp(velocity: .slow)
            } else if row.frame.minY < app.navigationBars.firstMatch.frame.maxY {
                list.swipeDown(velocity: .slow)
            } else {
                break
            }
        }
        XCTAssertTrue(
            row.wait(for: \.isHittable, toEqual: true, timeout: 10), "the row is on screen and takes touches")
        let thread = app.scrollViews["thread"]
        row.tap()
        // On a busy Mac running the whole check, the first tap can land while the app is still finishing its launch
        // transition and be dropped, with the list showing and nothing opened. One more tap opens it then.
        if !thread.waitForExistence(timeout: 5) { row.tap() }
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "the thread opens")
    }

    @MainActor
    private func launch(language: String, locale: String, size: String? = nil) -> XCUIApplication {
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus, "-conversationLayout", "chat",
                "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
            ] + (size.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
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
