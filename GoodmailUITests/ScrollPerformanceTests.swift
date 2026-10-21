import XCTest

/// The M1 performance spike: a 50k-thread synthetic mailbox, measured while flicking through it.
/// Opt-in, as it takes minutes: `TEST_RUNNER_GOODMAIL_PERF=1 xcodebuild test … -only-testing:GoodmailUITests/ScrollPerformanceTests`
final class ScrollPerformanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GOODMAIL_PERF"] != nil, "Set GOODMAIL_PERF=1 to run")
        continueAfterFailure = false
    }

    @MainActor
    func testTimeToFirstRowsWith50kThreads() throws {
        measure(metrics: [XCTClockMetric()]) {
            launchSyntheticMailbox()
        }
    }

    @MainActor
    func testScrollDecelerationWith50kThreads() throws {
        launchSyntheticMailbox()
        let list = app.collectionViews["mailbox"]
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            list.swipeDown(velocity: .fast)
        }
    }

    @MainActor
    private func launchSyntheticMailbox() {
        app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", ProcessInfo.processInfo.environment["GOODMAIL_PERF_THREADS"] ?? "50000",
            "-AppleLanguages", "(en)",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 60))
    }
}
