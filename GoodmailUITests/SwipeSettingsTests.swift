import XCTest

/// Swipe Actions in Settings: an action drags within its side, across to the other side and down to More Actions,
/// and the list stays whole, every row under its own header, after each change.
final class SwipeSettingsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAnActionDragsAcrossToTheOtherSide() {
        let app = openSwipeSettings(left: ["read", "star"], right: ["archive", "snooze"])
        drag(row("star", in: app), toTopOf: row("archive", in: app))
        // Where among the left side's rows it lands depends on how the rows shift under the finger.
        expectRows(["read"], under: "Swipe Right", ["archive", "snooze"], under: "Swipe Left", in: app)
        XCTAssertTrue(
            waitUntil { row("star", in: app).frame.minY > app.staticTexts["Swipe Left"].frame.maxY },
            "Star sits under Swipe Left")
        XCTAssertTrue(
            waitUntil { row("star", in: app).frame.maxY < app.staticTexts["More Actions"].frame.minY },
            "Star sits above More Actions")
    }

    @MainActor
    func testAnActionDraggedToMoreActionsLeavesItsSide() {
        let app = openSwipeSettings(left: ["read", "star"], right: ["archive", "snooze"])
        // The last row, as More Actions rises by a row once Snooze lifts off its side.
        drag(row("snooze", in: app), toTopOf: row("spam", in: app))
        expectRows(["read", "star"], under: "Swipe Right", ["archive"], under: "Swipe Left", in: app)
        XCTAssertTrue(
            waitUntil { row("snooze", in: app).frame.minY > app.staticTexts["More Actions"].frame.maxY },
            "Snooze moved down to More Actions")
    }

    @MainActor
    func testAnActionDroppedBelowTheLastRowOfAnotherSectionLands() {
        let app = openSwipeSettings(left: ["read", "star"], right: ["archive", "snooze"])
        // Below the last row, so the drop goes to the end of More Actions: animating that drop crashed the list.
        drag(row("snooze", in: app), to: row("spam", in: app), at: 1.5)
        XCTAssertEqual(app.state, .runningForeground, "the app quit on the drop")
        expectRows(["read", "star"], under: "Swipe Right", ["archive"], under: "Swipe Left", in: app)
        XCTAssertTrue(
            waitUntil { row("snooze", in: app).frame.minY > app.staticTexts["More Actions"].frame.maxY },
            "Snooze moved down to More Actions")
    }

    @MainActor
    func testDropsOntoAFullSideSnapBackAndTheNextDragStillWorks() {
        let app = openSwipeSettings(left: ["read", "star"], right: ["archive", "snooze", "trash"])
        // The list moved the row before the arrangement refused it, and the drag after that crashed on the row count.
        drag(row("star", in: app), toTopOf: row("archive", in: app), snapsBack: true)
        drag(row("read", in: app), to: row("trash", in: app), at: 0.8, snapsBack: true)
        XCTAssertEqual(app.state, .runningForeground, "the app quit on a drag after a refused drop")
        expectRows(
            ["read", "star"], under: "Swipe Right", ["archive", "snooze", "trash"], under: "Swipe Left", in: app)
        drag(row("read", in: app), toEndAfter: row("star", in: app))
        XCTAssertEqual(app.state, .runningForeground)
        expectRows(
            ["star", "read"], under: "Swipe Right", ["archive", "snooze", "trash"], under: "Swipe Left", in: app)
    }

    @MainActor
    func testReorderingInsideMoreActionsThenDraggingStillWorks() {
        let app = openSwipeSettings(left: ["read"], right: ["archive", "snooze", "trash"])
        // More Actions keeps its usual order, so the list takes the drop and then puts Star back above Report Spam.
        drag(row("spam", in: app), toTopOf: row("star", in: app), snapsBack: true)
        XCTAssertEqual(app.state, .runningForeground, "the app quit on a drop inside More Actions")
        XCTAssertTrue(
            waitUntil { isAbove(row("star", in: app).frame, row("spam", in: app).frame) },
            "Star went back above Report Spam")
        drag(row("star", in: app), toTopOf: row("read", in: app))
        XCTAssertEqual(app.state, .runningForeground, "the app quit on a drag after a drop inside More Actions")
        expectRows(
            ["star", "read"], under: "Swipe Right", ["archive", "snooze", "trash"], under: "Swipe Left", in: app)
        XCTAssertTrue(
            waitUntil { row("spam", in: app).frame.minY > app.staticTexts["More Actions"].frame.maxY },
            "Report Spam stayed in More Actions")
    }

    @MainActor
    func testAddingAnActionKeepsEveryRowInPlace() {
        let app = openSwipeSettings(left: ["read", "star"], right: ["archive", "snooze"])
        app.buttons["Add Trash"].tap()
        app.buttons["Add to Swipe Left"].tap()
        expectRows(
            ["read", "star"], under: "Swipe Right", ["archive", "snooze", "trash"], under: "Swipe Left", in: app)
        expectRemoveButtons(for: ["Read or Unread", "Star or Unstar", "Archive", "Snooze", "Trash"], in: app)
        attachScreenshot(of: app, named: "after adding Trash")
        // Then a drag, which pulled the header off its section after an add.
        drag(row("archive", in: app), toEndAfter: row("trash", in: app))
        expectRows(
            ["read", "star"], under: "Swipe Right", ["snooze", "trash", "archive"], under: "Swipe Left", in: app)
        expectRemoveButtons(for: ["Read or Unread", "Star or Unstar", "Archive", "Snooze", "Trash"], in: app)
        attachScreenshot(of: app, named: "after dragging Archive last")
    }

    @MainActor
    func testRemovingAnActionSetsItAsideWithItsAddMenu() {
        let app = openSwipeSettings(left: ["read", "star"], right: ["archive", "snooze"])
        app.buttons["Remove Snooze"].tap()
        expectRows(["read", "star"], under: "Swipe Right", ["archive"], under: "Swipe Left", in: app)
        XCTAssertTrue(app.buttons["Add Snooze"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Remove Snooze"].exists)
        XCTAssertTrue(
            waitUntil { row("snooze", in: app).frame.minY > app.staticTexts["More Actions"].frame.maxY },
            "Snooze moved down to More Actions")
    }

    /// Every action on a side shows its remove button, and none of them an add menu.
    @MainActor
    private func expectRemoveButtons(for titles: [String], in app: XCUIApplication) {
        for title in titles {
            XCTAssertTrue(app.buttons["Remove \(title)"].exists, "\(title) has no remove button")
            XCTAssertFalse(app.buttons["Add \(title)"].exists, "\(title) still has its add menu")
        }
    }

    /// Opens Swipe Actions with `left` and `right` stored, in English.
    @MainActor
    private func openSwipeSettings(left: [String], right: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "20", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-swipeLeadingActions", "(\(left.joined(separator: ",")))",
            "-swipeTrailingActions", "(\(right.joined(separator: ",")))",
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
        // The first match: Swipe Colors further down names every action again.
        return list.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Long-presses `source` and drops it on the top part of `target`, which places it before `target`.
    @MainActor
    private func drag(_ source: XCUIElement, toTopOf target: XCUIElement, snapsBack: Bool = false) {
        drag(source, to: target, at: 0.2, snapsBack: snapsBack)
    }

    /// Long-presses `source` and drops it on the bottom part of `target`, the last row of its section, which places it
    /// at the end of that section. A test that only needs some drag within a section to land uses this one: on a very
    /// busy Mac the list now and then reports a drop as the end of the section wherever the finger let go, and here
    /// that's the same place.
    @MainActor
    private func drag(_ source: XCUIElement, toEndAfter target: XCUIElement) {
        drag(source, to: target, at: 0.8)
    }

    /// Long-presses `source` and drops it at `height`, a fraction of `target`'s height down from its top. On a busy
    /// simulator a synthesized drag now and then lands where it started, as if the list never saw the finger move, so
    /// a drag that left the row where it was is made again, up to three times. Not when the drop `snapsBack` by
    /// design: there the row ending up where it started says nothing about the drag. The callers' checks on where the
    /// rows end up still decide the test.
    @MainActor
    private func drag(_ source: XCUIElement, to target: XCUIElement, at height: CGFloat, snapsBack: Bool = false) {
        XCTAssertTrue(source.waitForExistence(timeout: 5) && target.exists)
        let before = source.frame
        // Half a row of travel tells a move from the lift's jitter.
        let moved = { abs(source.frame.midY - before.midY) > before.height / 2 }
        for attempt in 1...3 where attempt == 1 || (!snapsBack && !waitUntil(timeout: 3, moved)) {
            let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: height))
            // A long hold at both ends: a busy simulator lifts the row late, and places the drop late, so a shorter
            // press moved the finger before the row came up, and a shorter rest let go while the list still placed the
            // row at the end of its section.
            start.press(forDuration: 2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
            // A busy simulator can be slow to start moving rows after the drop; the checks after the drag
            // catch a list that never settles.
            RunLoop.current.run(until: .now.addingTimeInterval(1))
            _ = source.waitUntilStill()
        }
    }

    /// Each side's rows sit below its header in this order, the right side's above the left one's, with no two rows
    /// or headers overlapping, once the list settles.
    @MainActor
    private func expectRows(
        _ right: [String], under rightHeader: String, _ left: [String], under leftHeader: String,
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let names = [rightHeader] + right + [leftHeader] + left
        func misplaced() -> [String] {
            let frames =
                [app.staticTexts[rightHeader].frame] + right.map { row($0, in: app).frame }
                + [app.staticTexts[leftHeader].frame] + left.map { row($0, in: app).frame }
            return zip(names.indices, names.indices.dropFirst()).compactMap { above, below in
                isAbove(frames[above], frames[below]) ? nil : "\(names[above]) sits above \(names[below])"
            }
        }
        // The list may still be moving rows after the last change, so the order is read once it holds or time runs
        // out, and the failure names what's out of place.
        _ = waitUntil { misplaced().isEmpty }
        for problem in misplaced() { XCTFail(problem, file: file, line: line) }
    }

    /// Whether `upper` sits above `lower`, allowing the point of overlap the list draws between neighboring rows.
    private func isAbove(_ upper: CGRect, _ lower: CGRect) -> Bool {
        upper.maxY <= lower.minY + 1
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
