import XCTest

/// The app's own intervals (`Signpost`): how long the list takes to show its first rows, and a conversation its first
/// message.
final class SignpostPerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        try PerformanceRun.requireOptIn()
        continueAfterFailure = false
    }

    @MainActor
    func testMailboxFirstRows() {
        let app = PerformanceRun.app()
        PerformanceRun.launchToRows(app)  // seeds the mailbox, outside the measured launches
        measure(metrics: [PerformanceRun.signpost("MailboxFirstRows")]) {
            PerformanceRun.launchToRows(app)
        }
    }

    @MainActor
    func testThreadOpen() throws {
        let app = PerformanceRun.app()
        app.launchArguments += AnimationSpeed.fast.arguments
        app.launch()
        try XCTSkipUnless(app.windows.firstMatch.horizontalSizeClass == .compact, "Opens and goes back on a phone")
        // A conversation only the test-mail corpus has, near the top. The list's first cell is a section header.
        let row = app.row(showing: "Saturday?")
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        let reader = app.scrollViews["thread"]
        let page = app.webViews.firstMatch

        // The metric takes the interval itself, so going back inside the block doesn't count. The interval ends with
        // the page's first layout, which grows it from its placeholder height.
        measure(metrics: [PerformanceRun.signpost("ThreadOpen")]) {
            XCTAssertTrue(retry({ row.tap() }, until: { reader.exists }), "the conversation opens")
            XCTAssertTrue(waitUntil { page.exists && page.frame.height > 1 }, "the first message's page lays out")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(reader.waitForNonExistence(timeout: 10), "Back goes to the list")
        }
    }
}
