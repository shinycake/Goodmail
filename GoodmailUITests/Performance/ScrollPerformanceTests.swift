import XCTest

/// The M1 performance spike: a 50k-thread synthetic mailbox, opened and flicked through. Opt-in, as it takes minutes:
/// `scripts/ui-suite --perf` runs it (`PerformanceRun`).
final class ScrollPerformanceTests: XCTestCase {
    private static let threads = 50_000

    override func setUpWithError() throws {
        try PerformanceRun.requireOptIn()
        continueAfterFailure = false
    }

    /// From the list being built to its first rows, on the large mailbox. The first launch seeds it and isn't measured.
    @MainActor
    func testFirstRowsWith50kThreads() throws {
        let app = PerformanceRun.app(threads: Self.threads)
        PerformanceRun.launchToRows(app)
        measure(metrics: [PerformanceRun.signpost("MailboxFirstRows")]) {
            PerformanceRun.launchToRows(app)
        }
    }

    @MainActor
    func testScrollDecelerationWith50kThreads() throws {
        let app = PerformanceRun.app(threads: Self.threads)
        PerformanceRun.launchToRows(app)
        let list = app.collectionViews["mailbox"]
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            list.swipeDown(velocity: .fast)
        }
    }
}
