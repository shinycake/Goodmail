import XCTest

/// A rule made in Settings shows in the list of rules, in English and in Hebrew.
final class RulesTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testARuleCanBeAdded() {
        addRule(
            language: "en", locale: "en_US",
            words: Words(
                settings: "Settings", rules: "Rules", addRule: "Add Rule", addCondition: "Add Condition",
                text: "Text", from: "From", subject: "Subject", value: "Value", addAction: "Add Action",
                snooze: "Snooze"))
    }

    @MainActor
    func testARuleCanBeAddedInHebrew() {
        addRule(
            language: "he", locale: "he_IL",
            words: Words(
                settings: "הגדרות", rules: "כללים", addRule: "הוספת כלל", addCondition: "הוספת תנאי", text: "טקסט",
                from: "מאת", subject: "נושא", value: "ערך", addAction: "הוספת פעולה", snooze: "נודניק"))
    }

    /// The labels the test reads, in the language it runs in.
    private struct Words {
        let settings, rules, addRule, addCondition, text, from, subject, value, addAction, snooze: String
    }

    @MainActor
    private func addRule(language: String, locale: String, words: Words) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "200", "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        if app.windows.firstMatch.horizontalSizeClass == .compact {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.buttons[words.settings].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[words.settings].waitForExistence(timeout: 5))
        let row = app.buttons[words.rules].firstMatch
        XCTAssertTrue(row.scrollIntoView(in: app), "Rules is in Settings")
        row.tap()

        let addRule = app.buttons[words.addRule].firstMatch
        XCTAssertTrue(addRule.waitForExistence(timeout: 5), "the rules load, with Add Rule")
        attach("\(language)-empty", app)
        addRule.tap()

        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the editor opens on the name")
        name.tap()
        name.typeText("Thursday night\n")

        // A new rule starts with one condition on the sender.
        let values = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", words.value))
        XCTAssertEqual(values.count, 1, "a new rule starts with one condition")
        values.element(boundBy: 0).tap()
        values.element(boundBy: 0).typeText("example.com\n")

        // Opening Add Condition adds nothing; choosing Text adds one, which is changed to Subject contains Y.
        app.buttons[words.addCondition].buttons.firstMatch.tap()
        let text = app.buttons[words.text].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "Add Condition offers Text")
        XCTAssertEqual(values.count, 1, "opening Add Condition adds nothing")
        text.tap()
        XCTAssertTrue(waitUntil { values.count == 2 }, "choosing Text adds one condition")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", words.from)).element(boundBy: 1).tap()
        app.buttons[words.subject].firstMatch.tap()
        values.element(boundBy: 1).tap()
        values.element(boundBy: 1).typeText("Y\n")

        // The same for Add Action: nothing until Snooze is chosen, then one action.
        let lengths = app.steppers
        let addAction = app.buttons[words.addAction].firstMatch
        XCTAssertTrue(addAction.scrollIntoView(in: app), "the editor offers Add Action")
        addAction.buttons.firstMatch.tap()
        let snooze = app.buttons[words.snooze].firstMatch
        XCTAssertTrue(snooze.waitForExistence(timeout: 5), "Add Action offers Snooze")
        XCTAssertEqual(lengths.count, 0, "opening Add Action adds nothing")
        snooze.tap()
        XCTAssertTrue(waitUntil { lengths.count == 1 }, "choosing Snooze adds one action")

        // Save is on once the rule reads, and the sheet's title becomes the rule's name.
        let editor = app.navigationBars["Thursday night"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "the rule reads")
        attach("\(language)-editor", app)
        // Read again once the editor has settled, so an extra row that landed after the polls above still shows.
        XCTAssertEqual(values.count, 2, "the rule has two conditions")
        XCTAssertEqual(lengths.count, 1, "the rule has one action")
        let save = editor.buttons.element(boundBy: editor.buttons.count - 1)
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 10), "Save is on")
        save.tap()

        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "saving closes the editor")
        XCTAssertTrue(
            app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Thursday night")).firstMatch
                .waitForExistence(timeout: 5), "the rule is listed")
        attach("\(language)-list", app)
    }

    @MainActor
    private func attach(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
