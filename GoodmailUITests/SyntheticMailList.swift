import XCTest

/// Reading the synthetic mailbox's list (`SyntheticMailbox`). Its conversations cycle through a few subjects in a fixed
/// order, so a row's subject tells it from its neighbors.
enum SyntheticMail {
    static let subjects = [
        "Lunch tomorrow?", "סיכום פגישה", "Your receipt from Apple", "Weekend plans", "[goodmail] CI passed",
        "Quarterly report draft — please review by Thursday", "תזכורת: תור לרופא", "Photos from the trip",
    ]

    /// The subject each conversation row in `list` shows, top to bottom. Section headers are cells too, and show none.
    @MainActor
    static func rowSubjects(in list: any XCUIElementSnapshot) -> [String] {
        list.children.filter { $0.elementType == .cell }.sorted { $0.frame.minY < $1.frame.minY }.compactMap { cell in
            let labels = labels(in: cell)
            return subjects.first { subject in labels.contains { $0.contains(subject) } }
        }
    }

    /// Every label in `snapshot` and below it.
    @MainActor
    static func labels(in snapshot: any XCUIElementSnapshot) -> [String] {
        [snapshot.label] + snapshot.children.flatMap(labels)
    }
}

extension XCUIApplication {
    /// The subjects of the first `count` conversations in `list`, top to bottom. It reads one snapshot of the list:
    /// cells bound by index re-resolve on every query, so asking each for its descendants mixes up rows.
    @MainActor
    func subjects(
        ofFirst count: Int, list: String = "mailbox", file: StaticString = #filePath, line: UInt = #line
    ) -> [String] {
        let rows = collectionViews[list]
        var found: [String] = []
        XCTAssertTrue(
            waitUntil {
                found = (try? rows.snapshot()).map(SyntheticMail.rowSubjects) ?? []
                return found.count >= count
            }, "the list shows \(count) conversations", file: file, line: line)
        let first = Array(found.prefix(count))
        XCTAssertEqual(
            Set(first).count, first.count, "neighboring rows have different subjects", file: file, line: line)
        return first
    }

    /// The first row in `list` that shows `subject`.
    @MainActor
    func row(showing subject: String, list: String = "mailbox") -> XCUIElement {
        collectionViews[list].cells.containing(NSPredicate(format: "label CONTAINS %@", subject)).firstMatch
    }
}
