import XCTest

/// After the reader archives the conversation they're reading, the window goes on as Settings says (R7): the one
/// below in the list, else the one above, else the list; or the list, set to Return to the List. Undo brings the
/// archived one back into the reader (R9), and Mark as Unread goes back to the list (R8). A tapped alert over an open
/// reader takes its place (R1). On iPhone and iPad.
final class AfterActionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testArchivingAMiddleConversationShowsTheOneBelow() {
        let app = launch()
        let rows = subjects(ofFirst: 3, in: app)
        open(rows[1], in: app)
        tapReaderAction("Archive", in: app)
        XCTAssertTrue(reads(rows[2], in: app), "the conversation below takes the reader's place")
        attach(app, "after-archive-next")
        assertBackGoesToTheList(in: app)
    }

    @MainActor
    func testArchivingTheLastConversationShowsTheOneAbove() {
        let app = launch()
        // Travel holds two conversations, neither in the Inbox, so Archive leaves both rows where they are.
        openMailbox("mailbox.Label_2.synthetic-1", in: app)
        let rows = subjects(ofFirst: 2, in: app)
        open(rows[1], in: app)
        tapReaderAction("Archive", in: app)
        XCTAssertTrue(reads(rows[0], in: app), "the conversation above takes the reader's place")
        attach(app, "after-archive-above")
    }

    @MainActor
    func testArchivingTheOnlyConversationShowsTheList() {
        let app = launch()
        // Receipts holds one conversation.
        openMailbox("mailbox.Label_1.synthetic-1", in: app)
        let rows = subjects(ofFirst: 1, in: app)
        open(rows[0], in: app)
        tapReaderAction("Archive", in: app)
        XCTAssertTrue(app.scrollViews["thread"].waitForNonExistence(timeout: 5), "nothing is left to read")
        XCTAssertTrue(app.collectionViews["mailbox"].isHittable, "the list shows")
        attach(app, "after-archive-only")
    }

    @MainActor
    func testReturnToTheListGoesBackToTheList() {
        let app = launch(afterRemoval: "list")
        let rows = subjects(ofFirst: 3, in: app)
        open(rows[1], in: app)
        tapReaderAction("Archive", in: app)
        XCTAssertTrue(app.scrollViews["thread"].waitForNonExistence(timeout: 5), "the reader closes")
        XCTAssertTrue(app.collectionViews["mailbox"].isHittable, "the list shows")
        attach(app, "after-archive-list")
    }

    @MainActor
    func testUndoReadsTheArchivedConversationAgain() {
        let app = launch()
        let rows = subjects(ofFirst: 3, in: app)
        open(rows[1], in: app)
        tapReaderAction("Archive", in: app)
        XCTAssertTrue(reads(rows[2], in: app))
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the toast offers Undo")
        undo.tap()
        XCTAssertTrue(reads(rows[1], in: app), "Undo brings the archived conversation back into the reader")
        attach(app, "after-undo")
        assertBackGoesToTheList(in: app)
    }

    @MainActor
    func testMarkAsUnreadGoesBackToTheList() {
        let app = launch()
        let rows = subjects(ofFirst: 3, in: app)
        open(rows[1], in: app)
        tapReaderAction("Mark as Unread", in: app)
        XCTAssertTrue(app.scrollViews["thread"].waitForNonExistence(timeout: 5), "the reader closes")
        XCTAssertTrue(
            app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", rows[1]))
                .firstMatch.waitForExistence(timeout: 5), "its row stays, for later")
        attach(app, "after-mark-unread")
    }

    /// A tapped alert for another conversation takes the open reader's place, and one Back still reaches the list.
    @MainActor
    func testAnAlertOverAnOpenReaderTakesItsPlace() {
        // t19 is in the first account's Inbox, as "Weekend plans" (`SyntheticMailbox`).
        let app = launch(extra: ["-GoodmailTestArrivalThread", "synthetic-1/t19", "-GoodmailTestArrivalAfter", "12"])
        let rows = subjects(ofFirst: 3, in: app).filter { $0 != "Weekend plans" }
        open(rows[0], in: app)
        XCTAssertTrue(
            waitUntil(timeout: 30) { app.staticTexts["thread.subject"].label == "Weekend plans" },
            "the alert's conversation replaces the one open")
        attach(app, "after-alert-over-reader")
        assertBackGoesToTheList(in: app)
    }

    /// Read from Snoozed, an archived conversation goes on to the next snoozed one.
    @MainActor
    func testArchivingFromSnoozedShowsTheNextSnoozed() {
        let app = launch(extra: ["-GoodmailSyntheticSnoozed", "YES"])
        openMailbox("mailbox.snoozed", in: app, list: "snoozed")
        let rows = subjects(ofFirst: 2, in: app, list: "snoozed")
        open(rows[0], in: app, list: "snoozed")
        tapReaderAction("Archive", in: app)
        XCTAssertTrue(reads(rows[1], in: app), "the next snoozed conversation takes the reader's place")
        attach(app, "after-archive-snoozed")
    }

    /// Under the Unread filter, Undo brings the archived conversation back into the reader and its row back into the
    /// list, though reading it marked it read.
    @MainActor
    func testUndoUnderTheUnreadFilterListsTheRowAgain() {
        let app = launch()
        let filter = app.buttons["listFilter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        let rows = subjects(ofFirst: 2, in: app)
        open(rows[0], in: app)
        tapReaderAction("Archive", in: app)
        XCTAssertTrue(reads(rows[1], in: app))
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(reads(rows[0], in: app), "Undo reads it again")
        if UIDevice.current.userInterfaceIdiom == .phone { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(
            app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", rows[0]))
                .firstMatch.waitForExistence(timeout: 5), "its row is listed again, read")
        attach(app, "after-undo-unread")
    }

    // MARK: Helpers

    /// The synthetic mailboxes' subjects (`SyntheticMailbox`), which tell their rows apart.
    private static let syntheticSubjects = [
        "Lunch tomorrow?", "סיכום פגישה", "Your receipt from Apple", "Weekend plans", "[goodmail] CI passed",
        "Quarterly report draft — please review by Thursday", "תזכורת: תור לרופא", "Photos from the trip",
    ]

    /// The synthetic mailboxes, seeded fresh each launch, with nothing arriving during the test. `afterRemoval` sets
    /// After Archive or Delete.
    @MainActor
    private func launch(afterRemoval: String = "next", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-GoodmailSyntheticThreads", "40", "-GoodmailSyntheticArrivalEvery", "3600",
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-afterRemoval", afterRemoval,
            ] + extra
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        return app
    }

    /// The subjects of the list's first `count` conversations, top to bottom, skipping the section headers.
    @MainActor
    private func subjects(
        ofFirst count: Int, in app: XCUIApplication, list: String = "mailbox", line: UInt = #line
    ) -> [String] {
        let cells = app.collectionViews[list].cells
        var found: [String] = []
        XCTAssertTrue(
            waitUntil {
                found = cells.allElementsBoundByIndex.compactMap { cell in
                    Self.syntheticSubjects.first { cell.label.contains($0) || shows($0, in: cell) }
                }
                return found.count >= count
            }, "the list shows \(count) conversations", line: line)
        let first = Array(found.prefix(count))
        XCTAssertEqual(Set(first).count, first.count, "neighboring rows have different subjects", line: line)
        return first
    }

    @MainActor
    private func shows(_ subject: String, in cell: XCUIElement) -> Bool {
        cell.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", subject)).firstMatch.exists
    }

    /// Opens the conversation whose row shows `subject`.
    @MainActor
    private func open(_ subject: String, in app: XCUIApplication, list: String = "mailbox", line: UInt = #line) {
        let row = app.collectionViews[list].cells.containing(NSPredicate(format: "label CONTAINS %@", subject))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), line: line)
        XCTAssertTrue(
            retry({ row.tap() }, until: { app.scrollViews["thread"].exists }), "the conversation opens", line: line)
        XCTAssertTrue(reads(subject, in: app), line: line)
    }

    /// Whether the reader shows the conversation with `subject`, within a few seconds.
    @MainActor
    private func reads(_ subject: String, in app: XCUIApplication) -> Bool {
        let shown = app.staticTexts["thread.subject"]
        return waitUntil(timeout: 10) { shown.exists && shown.label == subject }
    }

    /// Taps a reader action in the toolbar, or in its More menu when the bar runs short.
    @MainActor
    private func tapReaderAction(_ title: String, in app: XCUIApplication, line: UInt = #line) {
        let button = app.toolbars.buttons[title]
        if button.waitForExistence(timeout: 2), button.isHittable { return button.tap() }
        let more = app.buttons["BottomOverflowBarButtonItem"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "\(title) is in the toolbar or its More menu", line: line)
        more.tap()
        let item = app.buttons[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), line: line)
        item.tap()
    }

    /// Opens a mailbox from the mailboxes behind the list on a phone, or in the iPad's sidebar.
    @MainActor
    private func openMailbox(_ identifier: String, in app: XCUIApplication, list: String = "mailbox") {
        let cell = app.collectionViews["mailboxes"].cells[identifier].firstMatch
        if !cell.isHittable { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.collectionViews[list].cells.firstMatch.waitForExistence(timeout: 15))
    }

    /// On a phone, the reader that took another's place still goes back to the list, not to the one it replaced.
    @MainActor
    private func assertBackGoesToTheList(in app: XCUIApplication, line: UInt = #line) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.scrollViews["thread"].waitForNonExistence(timeout: 5), "one Back reaches the list", line: line)
        XCTAssertTrue(app.collectionViews["mailbox"].isHittable, line: line)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
