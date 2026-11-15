import XCTest

/// Swipe Actions in Settings: an action drags within its side, across to the other side and down to More Actions,
/// and the list stays whole, every row under its own header, after each change.
final class SwipeSettingsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAnActionDragsAcrossToTheOtherSide() {
        let app = openSwipeSettings(leading: ["read", "star"], trailing: ["archive", "snooze"])
        drag(row("star", in: app), toTopOf: row("archive", in: app))
        // Where among the left side's rows it lands depends on how the rows shift under the finger.
        expectRows(["read"], under: "Swipe Right", ["archive", "snooze"], under: "Swipe Left", in: app)
        XCTAssertGreaterThan(row("star", in: app).frame.minY, app.staticTexts["Swipe Left"].frame.maxY)
        XCTAssertLessThan(row("star", in: app).frame.maxY, app.staticTexts["More Actions"].frame.minY)
    }

    @MainActor
    func testAnActionDraggedToMoreActionsLeavesItsSide() {
        let app = openSwipeSettings(leading: ["read", "star"], trailing: ["archive", "snooze"])
        // The last row, as More Actions rises by a row once Snooze lifts off its side.
        drag(row("snooze", in: app), toTopOf: row("spam", in: app))
        expectRows(["read", "star"], under: "Swipe Right", ["archive"], under: "Swipe Left", in: app)
        XCTAssertGreaterThan(row("snooze", in: app).frame.minY, app.staticTexts["More Actions"].frame.maxY)
    }

    @MainActor
    func testAnActionDroppedBelowTheLastRowOfAnotherSectionLands() {
        let app = openSwipeSettings(leading: ["read", "star"], trailing: ["archive", "snooze"])
        // Below the last row, so the drop goes to the end of More Actions: animating that drop crashed the list.
        drag(row("snooze", in: app), to: row("spam", in: app), at: 1.5)
        XCTAssertEqual(app.state, .runningForeground, "the app quit on the drop")
        expectRows(["read", "star"], under: "Swipe Right", ["archive"], under: "Swipe Left", in: app)
        XCTAssertGreaterThan(row("snooze", in: app).frame.minY, app.staticTexts["More Actions"].frame.maxY)
    }

    @MainActor
    func testAddingAnActionKeepsEveryRowInPlace() {
        let app = openSwipeSettings(leading: ["read", "star"], trailing: ["archive", "snooze"])
        app.buttons["Add Trash"].tap()
        app.buttons["Add to Swipe Left"].tap()
        expectRows(
            ["read", "star"], under: "Swipe Right", ["archive", "snooze", "trash"], under: "Swipe Left", in: app)
        expectRemoveButtons(for: ["Read or Unread", "Star or Unstar", "Archive", "Snooze", "Trash"], in: app)
        attachScreenshot(of: app, named: "after adding Trash")
        // Then a drag, which pulled the header off its section after an add.
        drag(row("trash", in: app), toTopOf: row("archive", in: app))
        expectRows(
            ["read", "star"], under: "Swipe Right", ["trash", "archive", "snooze"], under: "Swipe Left", in: app)
        expectRemoveButtons(for: ["Read or Unread", "Star or Unstar", "Archive", "Snooze", "Trash"], in: app)
        attachScreenshot(of: app, named: "after dragging Trash first")
    }

    @MainActor
    func testRemovingAnActionSetsItAsideWithItsAddMenu() {
        let app = openSwipeSettings(leading: ["read", "star"], trailing: ["archive", "snooze"])
        app.buttons["Remove Snooze"].tap()
        expectRows(["read", "star"], under: "Swipe Right", ["archive"], under: "Swipe Left", in: app)
        XCTAssertTrue(app.buttons["Add Snooze"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Remove Snooze"].exists)
        XCTAssertGreaterThan(row("snooze", in: app).frame.minY, app.staticTexts["More Actions"].frame.maxY)
    }

    /// Every action on a side shows its remove button, and none of them an add menu.
    @MainActor
    private func expectRemoveButtons(for titles: [String], in app: XCUIApplication) {
        for title in titles {
            XCTAssertTrue(app.buttons["Remove \(title)"].exists, "\(title) has no remove button")
            XCTAssertFalse(app.buttons["Add \(title)"].exists, "\(title) still has its add menu")
        }
    }

    /// Opens Swipe Actions with `leading` and `trailing` stored, in English.
    @MainActor
    private func openSwipeSettings(leading: [String], trailing: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-swipeLeadingActions", "(\(leading.joined(separator: ",")))",
            "-swipeTrailingActions", "(\(trailing.joined(separator: ",")))",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        if app.windows.firstMatch.horizontalSizeClass == .compact {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Swipe Actions"].tap()
        XCTAssertTrue(app.navigationBars["Swipe Actions"].waitForExistence(timeout: 5))
        return app
    }

    /// A row's text, by the choice it shows.
    @MainActor
    private func row(_ choice: String, in app: XCUIApplication) -> XCUIElement {
        let titles = [
            "read": "Read or Unread", "star": "Star or Unstar", "archive": "Archive", "snooze": "Snooze",
            "trash": "Trash", "spam": "Report Spam",
        ]
        let title = titles[choice] ?? choice
        let list = app.collectionViews.containing(NSPredicate(format: "label == 'Swipe Right'")).firstMatch
        return list.staticTexts[title]
    }

    /// Long-presses `source` and drops it on the top part of `target`, which places it before `target`.
    @MainActor
    private func drag(_ source: XCUIElement, toTopOf target: XCUIElement) {
        drag(source, to: target, at: 0.2)
    }

    /// Long-presses `source` and drops it at `height`, a fraction of `target`'s height down from its top. On a busy
    /// simulator a synthesized long press now and then ends before the list lifts the row, so a drag that left the row
    /// where it was is made once more; the callers' checks on where the rows end up still decide the test.
    @MainActor
    private func drag(_ source: XCUIElement, to target: XCUIElement, at height: CGFloat) {
        XCTAssertTrue(source.waitForExistence(timeout: 5) && target.exists)
        let before = source.frame
        for _ in 1...2 where source.frame == before {
            let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: height))
            start.press(forDuration: 1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
            RunLoop.current.run(until: .now.addingTimeInterval(1))
        }
    }

    /// Each side's rows sit below its header in this order, the right side's above the left one's, with no two rows
    /// or headers overlapping.
    @MainActor
    private func expectRows(
        _ right: [String], under rightHeader: String, _ left: [String], under leftHeader: String,
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let frames =
            [app.staticTexts[rightHeader].frame] + right.map { row($0, in: app).frame }
            + [app.staticTexts[leftHeader].frame] + left.map { row($0, in: app).frame }
        let names = [rightHeader] + right + [leftHeader] + left
        for (above, below) in zip(frames.indices, frames.indices.dropFirst()) {
            XCTAssertLessThanOrEqual(
                frames[above].maxY, frames[below].minY + 1, "\(names[above]) sits above \(names[below])",
                file: file, line: line)
        }
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
