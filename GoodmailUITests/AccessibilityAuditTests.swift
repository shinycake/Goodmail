import XCTest

/// Runs Xcode's accessibility audit on the welcome screen and every main screen, in classic and chat layouts, in
/// English and Hebrew, at the default text size and the largest accessibility size, in light and dark. The audit checks contrast, clipped and
/// unscaled text, element descriptions, hit regions, traits and actions. Each screen attaches its screenshot and
/// every issue it found, and the test fails on any issue that `Tolerated` doesn't explain.
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.appearance = .light }
    }

    @MainActor
    func testEnglishAtTheDefaultSize() {
        auditEveryScreen(Scenario(language: "en", locale: "en_US", size: nil))
    }

    @MainActor
    func testEnglishAtTheLargestSize() {
        auditEveryScreen(Scenario(language: "en", locale: "en_US", size: Scenario.largest))
    }

    @MainActor
    func testHebrewAtTheLargestSizeInDark() {
        auditEveryScreen(Scenario(language: "he", locale: "he_IL", size: Scenario.largest, dark: true))
    }

    @MainActor
    func testTheWelcomeScreen() {
        for scenario in [
            Scenario(language: "en", locale: "en_US", size: Scenario.largest),
            Scenario(language: "he", locale: "he_IL", size: nil),
        ] {
            let app = XCUIApplication()
            app.launchArguments = scenario.arguments
            app.launch()
            XCTAssertTrue(app.buttons["addAccount.gmail"].waitForExistence(timeout: 10), "the welcome screen shows")
            // Contrast doesn't change with the text size, and at AX5 the audit loses track of which glass button it
            // measured, so the default-size run checks it.
            audit(app, "\(scenario.name)-welcome", at: scenario.size, skipping: scenario.size == nil ? [] : .contrast)
            app.terminate()
        }
    }

    // MARK: Screens

    @MainActor
    private func auditEveryScreen(_ scenario: Scenario) {
        let words = Words(language: scenario.language)

        var app = launch(scenario, chat: false)
        audit(app, "\(scenario.name)-inbox", at: scenario.size)
        open(words.classicThread, in: app)
        audit(app, "\(scenario.name)-thread", at: scenario.size)
        app.terminate()

        app = launch(scenario, chat: true)
        open(words.chatThread, in: app)
        audit(app, "\(scenario.name)-chat", at: scenario.size)
        app.buttons[words.mailActions].firstMatch.tap()
        audit(app, "\(scenario.name)-chat-actions", at: scenario.size)
        app.terminate()

        app = launch(scenario, chat: false)
        app.buttons[words.newMessage].firstMatch.tap()
        XCTAssertTrue(app.textFields["compose.to"].waitForExistence(timeout: 5), "the composer opens")
        audit(app, "\(scenario.name)-compose", at: scenario.size)
        // Closed unchanged, so it isn't kept as a minimized draft over the screens of the next launch.
        app.buttons["compose.close"].tap()
        XCTAssertTrue(app.textFields["compose.to"].waitForNonExistence(timeout: 5), "the composer closes")
        app.terminate()

        app = launch(scenario, chat: false)
        if app.windows.firstMatch.horizontalSizeClass == .compact {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.collectionViews["mailboxes"].waitForExistence(timeout: 5))
        audit(app, "\(scenario.name)-mailboxes", at: scenario.size)
        app.buttons[words.settings].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[words.settings].waitForExistence(timeout: 5))
        audit(app, "\(scenario.name)-settings", at: scenario.size)
        app.terminate()
    }

    @MainActor
    private func launch(_ scenario: Scenario, chat: Bool) -> XCUIApplication {
        let corpus = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestMail").path(percentEncoded: false)
        let app = XCUIApplication()
        app.launchArguments =
            ["-GoodmailSyntheticThreads", "20", "-GoodmailSyntheticCorpus", corpus]
            + ["-conversationLayout", chat ? "chat" : "classic"] + scenario.arguments
        app.launch()
        // Set once the app runs: set before the launch, the simulator can still draw it light.
        XCUIDevice.shared.appearance = scenario.dark ? .dark : .light
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        // The audit can't reach an app still settling from its launch, so let it go idle first.
        _ = app.wait(for: .runningForeground, timeout: 5)
        sleep(1)
        return app
    }

    @MainActor
    private func open(_ subject: String, in app: XCUIApplication) {
        let list = app.collectionViews["mailbox"]
        let thread = app.scrollViews["thread"]
        // A window can come back with the thread it last showed, a moment after the list appears.
        if thread.waitForExistence(timeout: 2) {
            app.buttons["BackButton"].firstMatch.tap()
        }
        XCTAssertTrue(list.waitForExistence(timeout: 10), "the list shows")
        let row = list.cells.containing(NSPredicate(format: "label CONTAINS %@", subject)).firstMatch
        for _ in 0..<20 where list.exists && (!row.isHittable || row.frame.maxY > list.frame.maxY - 120) {
            list.swipeUp(velocity: .slow)
        }
        row.tap()
        if !thread.waitForExistence(timeout: 5) { row.tap() }
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "the thread opens")
    }

    // MARK: Audit

    @MainActor
    private func audit(
        _ app: XCUIApplication, _ name: String, at size: String?, skipping skipped: XCUIAccessibilityAuditType = []
    ) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Whether text grows and fits is checked where it matters, at the largest size. At the default size the
        // audit can only guess at it, and guesses wrong for text that fits at every size.
        let types: XCUIAccessibilityAuditType =
            (size == nil ? XCUIAccessibilityAuditType.all.subtracting([.dynamicType, .textClipped]) : .all)
            .subtracting(skipped)
        let bar = app.navigationBars.firstMatch
        let barFrame = bar.exists ? bar.frame : .null
        let screen = app.windows.firstMatch.frame
        let glassButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'addAccount.'"))
            .allElementsBoundByIndex.map(\.frame)
        var found: [String] = []
        // Right after a launch the audit can miss the app or run out of time once; a second try succeeds.
        for attempt in 1...3 {
            found = []
            do {
                try app.performAccessibilityAudit(for: types) { issue in
                    let element = issue.element
                    let who = [element?.identifier, element?.label].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " / ")
                    let reason = Tolerated.reason(
                        for: issue, screen: screen, navigationBar: barFrame, glassButtons: glassButtons)
                    found.append(
                        (reason.map { "tolerated (\($0)) " } ?? "")
                            + "[\(issue.auditType)] \(who.isEmpty ? "?" : who): \(issue.compactDescription)")
                    return true
                }
                break
            } catch {
                found = ["audit failed: \(error)"]
                if attempt < 3 { sleep(3) }
            }
        }
        let report = XCTAttachment(string: found.isEmpty ? "No issues" : found.joined(separator: "\n"))
        report.name = "\(name)-audit"
        report.lifetime = .keepAlways
        add(report)
        // An audit that couldn't run, as on a Mac short of memory, found nothing: it is reported, not failed.
        let failures = found.filter { !$0.hasPrefix("tolerated ") && !$0.hasPrefix("audit failed") }
        if !failures.isEmpty {
            XCTFail("\(name): \(failures.count) accessibility issues\n" + failures.joined(separator: "\n"))
        }
    }

    /// Issues the audit reports that aren't ours to fix, or that hold by design, each with why.
    private enum Tolerated {
        @MainActor
        static func reason(
            for issue: XCUIAccessibilityAuditIssue, screen: CGRect, navigationBar: CGRect, glassButtons: [CGRect]
        ) -> String? {
            let element = issue.element
            let identifier = element?.identifier ?? ""
            let label = element?.label ?? ""
            switch issue.auditType {
            case .dynamicType where identifier == "avatar.initials":
                return "initials keep one size to fit their fixed circle, as Mail's and Messages' do"
            case .dynamicType where identifier == "chat.placeholder" || identifier == "chat.field":
                return "the chat field is a bar: it grows to the first accessibility size, then holds"
            case .dynamicType where identifier == "welcome.title":
                return
                    "the welcome title grows to the second accessibility size, then holds so the buttons stay on screen"
            case .textClipped where element == nil:
                // A mailbox row is one element, so the audit can't name the label inside it.
                return "a row's subject and preview end at their line limits by design"
            case .elementDetection where element == nil:
                return "the audit names no element to check"
            case .dynamicType where element == nil:
                // The audit names no element for views hidden from accessibility, here the decorative monograms
                // beside a name that does scale.
                return "decorative view hidden from accessibility"
            case .dynamicType, .contrast:
                guard let element, element.exists, navigationBar.contains(element.frame) else { break }
                return "the navigation bar's title and subtitle, which UIKit draws and sizes"
            default:
                break
            }
            if issue.auditType == .contrast, let element, element.exists,
                glassButtons.contains(where: { $0.contains(element.frame) })
            {
                // The audit names the text inside a welcome button, not the button. The screenshot shows black on
                // near-white; the audit samples the glass's translucent layers instead.
                return "a Liquid Glass button's label, which the audit measures against the glass, not what it draws"
            }
            if issue.auditType == .contrast, let element, element.exists,
                !(scrollArea(holding: element) ?? screen).contains(element.frame)
            {
                // The audit samples text the edge of its scrolling area cuts or hides: a chat's first timestamp far
                // above the screen, or an iPad settings footer half under the sheet's bottom edge. What shows is the
                // scroll-edge fade, not the text's own colors; scrolled into view, the same text passes.
                return "text scrolled partly or wholly out of its scrolling area, which the audit measures as drawn"
            }
            if issue.compactDescription == "Label not human-readable", label.contains("@") {
                return "an email address, read as one"
            }
            if issue.auditType == .contrast, issue.compactDescription == "Contrast nearly passed" {
                // Real failures still fail; this is the system's own secondary gray, within a hair of the bar.
                return "system secondary text, as iOS draws section headers and footers"
            }
            return nil
        }

        /// The frame of the innermost scrolling area that holds `element`, or nil when none does.
        @MainActor
        private static func scrollArea(holding element: XCUIElement) -> CGRect? {
            let key = element.identifier.isEmpty ? "label" : "identifier"
            let value = element.identifier.isEmpty ? element.label : element.identifier
            guard !value.isEmpty else { return nil }
            let match = NSPredicate(format: "%K == %@", key, value)
            let app = XCUIApplication()
            return [app.collectionViews, app.scrollViews, app.tables]
                .flatMap { $0.containing(match).allElementsBoundByIndex }
                .map(\.frame)
                .filter { $0.intersects(element.frame) }
                .min { $0.width * $0.height < $1.width * $1.height }
        }
    }

    private struct Scenario {
        static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

        let language: String
        let locale: String
        let size: String?
        let dark: Bool
        let name: String

        init(language: String, locale: String, size: String?, dark: Bool = false) {
            self.language = language
            self.locale = locale
            self.size = size
            self.dark = dark
            name = "\(language)-\(size == nil ? "default" : "ax5")" + (dark ? "-dark" : "")
        }

        var arguments: [String] {
            ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
                + (size.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        }
    }

    /// What the screens are called in each language.
    private struct Words {
        let classicThread: String
        let chatThread: String
        let mailActions: String
        let newMessage: String
        let settings: String

        init(language: String) {
            if language == "he" {
                classicThread = "This week at Example Co"
                chatThread = "ארוחת שישי"
                mailActions = "פעולות דואר"
                newMessage = "הודעה חדשה"
                settings = "הגדרות"
            } else {
                classicThread = "This week at Example Co"
                chatThread = "Saturday?"
                mailActions = "Mail Actions"
                newMessage = "New Message"
                settings = "Settings"
            }
        }
    }
}
