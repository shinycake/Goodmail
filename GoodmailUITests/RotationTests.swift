import XCTest

/// Turning a phone wide enough to show columns in landscape, as an iPhone Pro Max, mid-read keeps what the reader
/// was doing as the window changes arrangement: the search and its results, and the conversation open over them and
/// then beside them, the same screens rather than new ones, whose chat reply still takes attachments (D8). A device
/// whose width class doesn't change as it turns, as a full-screen iPad, has nothing to test here.
final class RotationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testTurningMidReadKeepsTheSearchTheReaderAndItsAttachments() throws {
        let (app, field, subject) = try openSearchResult(language: "en")
        let window = app.windows.firstMatch

        XCUIDevice.shared.orientation = .landscapeLeft
        guard waitUntil(timeout: 5, { window.horizontalSizeClass == .regular }) else {
            throw XCTSkip("this device stays narrow on its side, so the arrangement never changes")
        }
        expectKept(subject: subject, field: field, besideEachOther: true)
        attach(app, "rotation-landscape")
        attachAPhoto(in: app)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil { window.horizontalSizeClass == .compact }, "the arrangement turns back")
        expectKept(subject: subject, field: field, besideEachOther: false)
        XCTAssertTrue(
            waitUntil { attachment(in: app).exists }, "the photo attached beside the list is still on the reply")
        attach(app, "rotation-portrait")
    }

    /// On a phone on its side the list's column is short, and the toolbar under it, with New Message and the accounts'
    /// status, must not sit on the one result it has room for, in either reading direction.
    @MainActor
    func testTurningMidSearchLeavesAResultClearOfTheToolbar() throws {
        for language in ["en", "he"] {
            let (app, _, _) = try openSearchResult(language: language)
            XCUIDevice.shared.orientation = .landscapeLeft
            guard waitUntil(timeout: 5, { app.windows.firstMatch.horizontalSizeClass == .regular }) else {
                throw XCTSkip("this device stays narrow on its side, so the arrangement never changes")
            }
            let clear = waitUntil { Self.aResultClearsTheToolbar(in: app) }
            attach(app, "landscape-search-\(language)")
            XCTAssertTrue(clear, "a result clears the toolbar in \(language)")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    /// Launches upright in `language`, searches for "plans" and opens the result over the list, returning the search
    /// field and the reader's bar, whose title is the conversation's subject.
    @MainActor
    private func openSearchResult(language: String) throws -> (XCUIApplication, XCUIElement, XCUIElement) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-GoodmailSyntheticThreads", "40", "-GoodmailSyntheticArrivalEvery", "3600", "-conversationLayout", "chat",
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "he" ? "he_IL" : "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["mailbox"].cells.firstMatch.waitForExistence(timeout: 15))
        try XCTSkipUnless(app.windows.firstMatch.horizontalSizeClass == .compact, "a window narrow upright")

        let field = app.searchFields.firstMatch
        if !field.exists {
            let search = app.buttons.matching(NSPredicate(format: "label IN {'Search', 'חיפוש'}")).firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("plans")
        let result = app.cells.containing(NSPredicate(format: "label CONTAINS 'Weekend plans'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), "search finds it")
        // The synthetic conversations have no messages for a service to bring, so the reader opens on its subject,
        // its bar's title, and says it couldn't load them; its reply bar is what a turn must keep.
        let subject = app.navigationBars["Weekend plans"]
        XCTAssertTrue(
            retry({ Self.results().first(where: \.isHittable)?.tap() }, until: { subject.exists }, timeout: 10),
            "the conversation opens")
        XCTAssertTrue(
            waitUntil { Self.results().allSatisfy { !$0.isHittable } }, "narrow, the reader covers the results")
        return (app, field, subject)
    }

    /// Whether a result lies wholly on screen with none of the toolbar's buttons over it. Hittable isn't enough: it
    /// probes only the row's middle, which a button at the row's end leaves clear.
    @MainActor
    private static func aResultClearsTheToolbar(in app: XCUIApplication) -> Bool {
        // One snapshot, since the toolbars' buttons come and go as the columns settle.
        guard let snapshot = try? app.snapshot() else { return false }
        let window = app.windows.firstMatch.frame
        let buttons = toolbarButtons(in: snapshot, inToolbar: false)
        return results().contains { row in
            window.contains(row.frame) && !buttons.contains { $0.intersects(row.frame) }
        }
    }

    @MainActor
    private static func toolbarButtons(in snapshot: any XCUIElementSnapshot, inToolbar: Bool) -> [CGRect] {
        let inToolbar = inToolbar || snapshot.elementType == .toolbar
        let own = inToolbar && snapshot.elementType == .button ? [snapshot.frame] : []
        return own + snapshot.children.flatMap { toolbarButtons(in: $0, inToolbar: inToolbar) }
    }

    /// The reader and the search as they were: beside each other in columns, the reader over the results on the stack.
    @MainActor
    private func expectKept(
        subject: XCUIElement, field: XCUIElement, besideEachOther: Bool
    ) {
        XCTAssertTrue(waitUntil { subject.exists }, "the reader stays")
        if besideEachOther {
            XCTAssertTrue(waitUntil { field.exists && field.value as? String == "plans" }, "the search stays as typed")
            XCTAssertTrue(
                waitUntil { Self.aResultClearsTheToolbar(in: XCUIApplication()) },
                "and a result shows beside the reader, clear of the toolbar")
        } else {
            XCTAssertTrue(
                waitUntil { Self.results().allSatisfy { !$0.isHittable } }, "the reader covers the results again")
        }
    }

    /// Every row that reads "Weekend plans": the search's results, and the mailbox's own rows underneath them, so a
    /// check holds for all of them rather than for whichever comes first.
    @MainActor
    private static func results() -> [XCUIElement] {
        XCUIApplication().cells.containing(NSPredicate(format: "label CONTAINS 'Weekend plans'"))
            .allElementsBoundByIndex.filter(\.exists)
    }

    /// Attaches a photo from the library to the chat reply, which a reader moved between arrangements must still take.
    @MainActor
    private func attachAPhoto(in app: XCUIApplication) {
        let plus = app.buttons["Attach"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        let library = app.buttons["Photo Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        // The picker's first images are its icons; a photo's name is "Photo, " and when it was taken.
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo, '")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "the simulator's library has photos")
        photo.tap()
        let add = app.buttons["Add"].firstMatch
        if add.waitForExistence(timeout: 3) { add.tap() }
        XCTAssertTrue(waitUntil(timeout: 15) { attachment(in: app).exists }, "the photo lands on the reply")
    }

    /// A file's capsule on the reply, which reads its name and then its size.
    @MainActor
    private func attachment(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' KB' OR label CONTAINS ' MB'")).firstMatch
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        // The window's own, since the app's screenshot comes out cropped to a square on a phone on its side.
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
