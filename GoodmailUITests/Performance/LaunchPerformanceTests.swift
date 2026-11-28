import XCTest

/// How long the app takes to launch on a seeded synthetic mailbox: until it responds, as the system sees it, and until
/// its list shows its first rows (`Launch`).
final class LaunchPerformanceTests: XCTestCase {
    override func setUpWithError() throws {
        try PerformanceRun.requireOptIn()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() {
        let app = PerformanceRun.app()
        // Seeds the mailbox, which only the first launch after an install does, so no measured launch includes it.
        PerformanceRun.launchToRows(app)
        app.terminate()

        // The app's own `Launch` interval runs on to the list's first rows, so each launch waits for them.
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), PerformanceRun.signpost("Launch")]) {
            PerformanceRun.launchToRows(app)
        }
    }
}
