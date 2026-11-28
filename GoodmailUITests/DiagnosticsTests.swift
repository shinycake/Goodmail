import XCTest

/// Settings > Diagnostics lists the reports the system sent, by day, and opens each one's figures, in English and in
/// Hebrew. The app is seeded with the fixtures the FieldDiagnostics tests decode, since a simulator gets no reports.
final class DiagnosticsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheReportsShowByDayAndOpen() {
        showDiagnostics(
            language: "en", locale: "en_US", settings: "Settings", diagnostics: "Diagnostics", crash: "Crash",
            summary: "Daily Summary", hangs: "Hangs")
    }

    @MainActor
    func testTheReportsShowByDayAndOpenInHebrew() {
        showDiagnostics(
            language: "he", locale: "he_IL", settings: "הגדרות", diagnostics: "אבחון", crash: "קריסה",
            summary: "סיכום יומי", hangs: "תקיעות")
    }

    @MainActor
    private func showDiagnostics(
        language: String, locale: String, settings: String, diagnostics: String, crash: String, summary: String,
        hangs: String
    ) {
        let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Packages/FieldDiagnostics/Tests/FieldDiagnosticsTests/Fixtures").path(
                percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-GoodmailSeedDiagnostics", fixtures, "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        if app.windows.firstMatch.horizontalSizeClass == .compact {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.buttons[settings].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[settings].waitForExistence(timeout: 5))

        let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", diagnostics)).firstMatch
        XCTAssertTrue(row.scrollIntoView(in: app), "Diagnostics is in Settings")
        row.tap()
        XCTAssertTrue(app.navigationBars[diagnostics].waitForExistence(timeout: 5))

        let crashRow = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", crash)).firstMatch
        XCTAssertTrue(crashRow.waitForExistence(timeout: 10), "the seeded crash is listed")
        XCTAssertTrue(
            app.staticTexts["EXC_BAD_ACCESS"].exists, "the crash's row names its exception, in any language")
        attachScreenshot(of: app, named: "diagnostics-\(language)")

        crashRow.tap()
        XCTAssertTrue(app.navigationBars[crash].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SIGSEGV"].exists, "the crash's page shows its signal")
        app.navigationBars[crash].buttons.element(boundBy: 0).tap()

        let summaryRow = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", summary)).firstMatch
        XCTAssertTrue(summaryRow.waitForExistence(timeout: 5))
        summaryRow.tap()
        XCTAssertTrue(app.navigationBars[summary].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[hangs].firstMatch.exists, "the day's figures show its hangs")
        attachScreenshot(of: app, named: "diagnostics-summary-\(language)")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
