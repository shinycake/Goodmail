import XCTest

/// A tapped alert, or anything else from outside the window, uncovers it and shows the conversation in a list that
/// holds it (R3, R4): over the composer, the drafts laid out, Settings, search and Select mode, from another account's
/// list or another Inbox category; beneath an alert, which stays; and a conversation that is gone is said to be
/// (R10). The arrival is `-GoodmailTestArrivalThread` (`TestArrival`), as a tap on an alert opens it. On iPhone and
/// iPad.
final class ArrivalTests: XCTestCase {
    /// t19 is in the first account's Inbox, Primary, as "Weekend plans" (`SyntheticMailbox`).
    private static let weekendPlans = "Weekend plans"
    /// t29 is in the first account's Inbox under Promotions.
    private static let promotion = "Quarterly report draft — please review by Thursday"
    private static let gone = "That conversation is no longer available."

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheSameConversationOpenStaysAsItIs() {
        let app = launch(arriving: "t19")
        open(Self.weekendPlans, in: app)
        XCTAssertTrue(arrived(in: app))
        assertOneBackReachesTheList(in: app)
        attach(app, "arrival-same")
    }

    @MainActor
    func testTheComposerGoesDownToThePill() {
        let app = launch(arriving: "t19")
        write("Lunch", in: app)
        XCTAssertTrue(reads(Self.weekendPlans, in: app, within: 30), "the conversation shows")
        XCTAssertFalse(app.textFields["compose.subject"].exists, "the composer went down")
        if UIDevice.current.userInterfaceIdiom == .phone { app.navigationBars.buttons.element(boundBy: 0).tap() }
        let pill = app.toolbars.buttons["drafts.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the message waits in the pill")
        XCTAssertEqual(pill.label, "1 Draft")
        attach(app, "arrival-composer")
    }

    @MainActor
    func testTheDraftsLaidOutFoldAway() {
        let app = launch(arriving: "t19", after: 40)
        write("Lunch", in: app)
        minimize(app)
        write("Budget", in: app)
        minimize(app)
        let pill = app.toolbars.buttons["drafts.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.tap()
        let cards = app.otherElements.matching(identifier: "drafts.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5), "the drafts are laid out")
        XCTAssertTrue(reads(Self.weekendPlans, in: app, within: 45))
        XCTAssertFalse(cards.firstMatch.exists, "the picker folded away")
        attach(app, "arrival-drafts")
    }

    @MainActor
    func testSettingsClosesEvenAPageDeep() {
        let app = launch(arriving: "t19")
        openMailboxes(in: app)
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Swipe Actions"].tap()
        XCTAssertTrue(app.navigationBars["Swipe Actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(arrived(in: app))
        XCTAssertFalse(app.navigationBars["Swipe Actions"].exists, "Settings closed as its Close button does")
        assertOneBackReachesTheList(in: app)
        attach(app, "arrival-settings")
    }

    @MainActor
    func testAnAlertStaysAndTheConversationShowsBeneathIt() {
        let app = launch(arriving: "t19")
        openMailbox("mailbox.TRASH", in: app)
        let deleteForever = app.buttons["Delete Forever"]
        XCTAssertTrue(app.collectionViews["mailbox"].cells.element(boundBy: 1).swipeOpen(showing: deleteForever))
        deleteForever.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(alert.waitForNonExistence(timeout: 20), "the arrival leaves the alert up")
        attach(app, "arrival-under-alert")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(reads(Self.weekendPlans, in: app, within: 5), "the conversation is beneath it")
    }

    @MainActor
    func testSearchEnds() {
        let app = launch(arriving: "t19")
        let search = app.navigationBars.buttons["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(arrived(in: app))
        assertOneBackReachesTheList(in: app)
        XCTAssertFalse(app.searchFields.firstMatch.exists, "search ended")
        attach(app, "arrival-search")
    }

    @MainActor
    func testSelectModeEnds() {
        let app = launch(arriving: "t19")
        app.navigationBars.buttons["Select"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(arrived(in: app))
        assertOneBackReachesTheList(in: app)
        XCTAssertTrue(app.navigationBars.buttons["Select"].waitForExistence(timeout: 5), "Select mode ended")
        attach(app, "arrival-select")
    }

    @MainActor
    func testAnotherAccountsListGivesWayToTheInbox() {
        let app = launch(arriving: "t19")
        openMailbox("mailbox.Label_3.synthetic-2", in: app)
        XCTAssertTrue(arrived(in: app))
        assertOneBackReachesTheList(in: app)
        XCTAssertTrue(listed(Self.weekendPlans, in: app), "its row is in the list behind it")
        attach(app, "arrival-other-account")
    }

    @MainActor
    func testTheInboxShowsTheConversationsCategory() {
        let app = launch(arriving: "t29")
        XCTAssertTrue(reads(Self.promotion, in: app, within: 30))
        assertOneBackReachesTheList(in: app)
        XCTAssertTrue(listed(Self.promotion, in: app), "the Inbox shows Promotions, with its row")
        attach(app, "arrival-category")
    }

    @MainActor
    func testAConversationGoneIsSaidToBe() {
        let app = launch(arriving: "no-such-thread")
        XCTAssertTrue(app.staticTexts[Self.gone].waitForExistence(timeout: 40), "the window says it is gone")
        XCTAssertFalse(app.scrollViews["thread"].exists, "nothing opens")
        XCTAssertTrue(app.collectionViews["mailbox"].exists, "the Inbox shows")
        attach(app, "arrival-gone")
    }

    @MainActor
    func testAColdLaunchOpensTheConversation() {
        let app = launch(arriving: "t19", after: 0)
        XCTAssertTrue(reads(Self.weekendPlans, in: app, within: 15))
        assertOneBackReachesTheList(in: app)
        attach(app, "arrival-cold-launch")
    }

    // MARK: Helpers

    /// The synthetic mailboxes, with the first account's `thread` arriving from outside `after` seconds from launch.
    @MainActor
    private func launch(arriving thread: String, after seconds: Int = 15) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "40", "-GoodmailSyntheticArrivalEvery", "3600",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-GoodmailTestArrivalThread", "synthetic-1/\(thread)", "-GoodmailTestArrivalAfter", "\(seconds)",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].waitForExistence(timeout: 15))
        return app
    }

    /// Whether "Weekend plans" arrived in the reader.
    @MainActor
    private func arrived(in app: XCUIApplication) -> Bool {
        reads(Self.weekendPlans, in: app, within: 30)
    }

    @MainActor
    private func reads(_ subject: String, in app: XCUIApplication, within timeout: TimeInterval) -> Bool {
        let shown = app.staticTexts["thread.subject"]
        return waitUntil(timeout: timeout) { shown.exists && shown.label == subject }
    }

    @MainActor
    private func listed(_ subject: String, in app: XCUIApplication) -> Bool {
        app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", subject)).firstMatch
            .waitForExistence(timeout: 5)
    }

    /// Opens the conversation whose row shows `subject`.
    @MainActor
    private func open(_ subject: String, in app: XCUIApplication, line: UInt = #line) {
        let row = app.collectionViews["mailbox"].cells.containing(NSPredicate(format: "label CONTAINS %@", subject))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), line: line)
        XCTAssertTrue(
            retry({ row.tap() }, until: { app.scrollViews["thread"].exists }), "the conversation opens", line: line)
    }

    /// The mailboxes, behind the list on a phone, or in the iPad's sidebar.
    @MainActor
    private func openMailboxes(in app: XCUIApplication) {
        if app.windows.firstMatch.horizontalSizeClass == .compact {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    @MainActor
    private func openMailbox(_ identifier: String, in app: XCUIApplication) {
        let cell = app.collectionViews["mailboxes"].cells[identifier].firstMatch
        if !cell.isHittable { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
    }

    /// Starts a message from Compose with `subject`.
    @MainActor
    private func write(_ subject: String, in app: XCUIApplication) {
        app.toolbars.buttons["New Message"].tap()
        let field = app.textFields["compose.subject"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the composer opens")
        field.tap()
        field.typeText(subject)
    }

    /// Pulls the composer's card down by its navigation bar to the bottom of the screen.
    @MainActor
    private func minimize(_ app: XCUIApplication) {
        let bar = app.navigationBars.element(boundBy: app.navigationBars.count - 1)
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// On a phone, one Back from the conversation reaches the list (R1).
    @MainActor
    private func assertOneBackReachesTheList(in app: XCUIApplication, line: UInt = #line) {
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
