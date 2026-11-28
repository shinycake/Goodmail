import XCTest

/// What the performance tests share. They take minutes and want the Mac to themselves, so they run only when asked:
/// `scripts/ui-suite --perf` sets `GOODMAIL_PERF`, runs them alone on one simulator and compares their medians with
/// `baselines.json` (`scripts/perf-compare`).
enum PerformanceRun {
    static func requireOptIn() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GOODMAIL_PERF"] != nil, "Set GOODMAIL_PERF=1 to run")
    }

    /// The size of the synthetic mailbox the launch and signpost tests open.
    static let threads = 2_000

    /// The app's own interval named `name` (`Signpost` in MailCore).
    static func signpost(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: "com.idanbirman.goodmail", category: "Performance", name: name)
    }

    /// The app on a synthetic mailbox of `threads` conversations, not yet launched. The test-mail corpus (`TestMail`)
    /// is on top, so the first conversations have messages to open. The app seeds a mailbox of each size on its first
    /// launch and reuses it after, so a test launches once before it measures. It files the corpus's 21 messages again
    /// on every launch, so every measured launch includes that.
    @MainActor
    static func app(threads: Int = threads) -> XCUIApplication {
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments =
            ["-GoodmailSyntheticThreads", "\(threads)", "-GoodmailSyntheticCorpus", corpus]
            + AppLanguage.english.arguments
        return app
    }

    /// Launches `app` and waits for its mailbox's first rows.
    @MainActor
    static func launchToRows(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 60))
    }
}
