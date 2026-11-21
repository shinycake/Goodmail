import MailCore
import Testing

/// Picking rows with a pointer and keys, as in Apple Mail: a click reads one row, ⌘ adds or removes, ⇧ extends from
/// the anchor, and a row that leaves drops out of the pick.
struct ListSelectionTests {
    private static func row(_ name: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: name)
    }

    private let a = row("a"), b = row("b"), c = row("c"), d = row("d"), e = row("e")
    private var rows: [ThreadSummary.ID] { [a, b, c, d, e] }

    // MARK: Clicks

    @Test func aPlainClickReadsTheRow() {
        #expect(ListSelection.none.clicking(b, .plain, in: rows) == .reading(b))
        #expect(ListSelection.reading(a).clicking(b, .plain, in: rows) == .reading(b))
        #expect(ListSelection.several([a, c], anchor: c).clicking(d, .plain, in: rows) == .reading(d))
    }

    @Test func commandClickAddsARowToTheOneBeingRead() {
        #expect(ListSelection.reading(a).clicking(c, .toggle, in: rows) == .several([a, c], anchor: c))
        #expect(ListSelection.none.clicking(c, .toggle, in: rows) == .reading(c), "nothing to add to")
        #expect(
            ListSelection.reading(a).clicking(c, .toggle, in: [b, c]) == .reading(c),
            "one still read after its row left isn't picked along, where Delete would take it unseen")
    }

    @Test func commandClickTakesARowAwayAndOneLeftIsRead() {
        #expect(
            ListSelection.several([a, b, c], anchor: c).clicking(b, .toggle, in: rows) == .several([a, c], anchor: c))
        #expect(ListSelection.several([a, c], anchor: c).clicking(c, .toggle, in: rows) == .reading(a))
        #expect(ListSelection.reading(a).clicking(a, .toggle, in: rows) == .none)
    }

    @Test func shiftClickExtendsFromTheAnchorEitherWay() {
        #expect(ListSelection.reading(b).clicking(d, .extend, in: rows) == .several([b, c, d], anchor: b))
        #expect(ListSelection.reading(d).clicking(b, .extend, in: rows) == .several([b, c, d], anchor: d))
        // A second ⇧-click replaces the range rather than adding to it.
        #expect(
            ListSelection.several([b, c, d], anchor: b).clicking(c, .extend, in: rows) == .several([b, c], anchor: b))
        #expect(
            ListSelection.several([a, e], anchor: e).clicking(c, .extend, in: rows) == .several([c, d, e], anchor: e))
    }

    @Test func shiftClickWithoutAnAnchorInTheListIsAPlainClick() {
        #expect(ListSelection.none.clicking(c, .extend, in: rows) == .reading(c))
        #expect(ListSelection.reading(Self.row("gone")).clicking(c, .extend, in: rows) == .reading(c))
        #expect(ListSelection.reading(c).clicking(c, .extend, in: rows) == .reading(c))
    }

    // MARK: Arrows

    @Test func arrowsMoveTheRowBeingReadAndStopAtTheEnds() {
        #expect(ListSelection.reading(b).moving(1, extending: false, in: rows) == .reading(c))
        #expect(ListSelection.reading(b).moving(-1, extending: false, in: rows) == .reading(a))
        #expect(ListSelection.reading(a).moving(-1, extending: false, in: rows) == .reading(a))
        #expect(ListSelection.reading(e).moving(1, extending: false, in: rows) == .reading(e))
    }

    @Test func arrowsFromNothingStartAtTheTop() {
        #expect(ListSelection.none.moving(1, extending: false, in: rows) == .reading(a))
        #expect(ListSelection.none.moving(-1, extending: true, in: rows) == .reading(a))
        #expect(ListSelection.none.moving(1, extending: false, in: []) == .none)
    }

    @Test func arrowsLeaveSeveralFromTheirEdge() {
        #expect(ListSelection.several([b, c], anchor: b).moving(1, extending: false, in: rows) == .reading(d))
        #expect(ListSelection.several([b, c], anchor: b).moving(-1, extending: false, in: rows) == .reading(a))
    }

    @Test func shiftArrowsGrowAndShrinkFromTheAnchor() {
        let down = ListSelection.reading(b).moving(1, extending: true, in: rows)
        #expect(down == .several([b, c], anchor: b))
        let further = down.moving(1, extending: true, in: rows)
        #expect(further == .several([b, c, d], anchor: b))
        #expect(further.moving(-1, extending: true, in: rows) == .several([b, c], anchor: b))
        #expect(down.moving(-1, extending: true, in: rows) == .reading(b), "back to the anchor alone")
        let up = ListSelection.reading(c).moving(-1, extending: true, in: rows)
        #expect(up == .several([b, c], anchor: c))
        #expect(up.moving(-1, extending: true, in: rows) == .several([a, b, c], anchor: c))
        #expect(up.moving(1, extending: true, in: rows) == .reading(c))
    }

    // MARK: Select All, Escape and right-click

    @Test func selectAllKeepsTheAnchor() {
        #expect(ListSelection.reading(c).selectingAll(in: rows) == .several(Set(rows), anchor: c))
        #expect(ListSelection.none.selectingAll(in: rows) == .several(Set(rows), anchor: a))
        #expect(ListSelection.none.selectingAll(in: [b]) == .reading(b))
        #expect(ListSelection.none.selectingAll(in: []) == .none)
    }

    @Test func escapeDropsSeveralBackToTheAnchor() {
        #expect(ListSelection.several([a, b, c], anchor: b).dropped == .reading(b))
        #expect(ListSelection.several([a, b], anchor: nil).dropped == .none)
        #expect(ListSelection.reading(a).dropped == .reading(a))
    }

    @Test func aMenuOnARowInTheSelectionIsForAllOfIt() {
        let selection = ListSelection.several([b, c], anchor: b)
        #expect(selection.acting(on: c) == [b, c])
        #expect(selection.acting(on: e) == [e])
        #expect(ListSelection.reading(a).acting(on: a) == [a])
        #expect(ListSelection.reading(a).acting(on: b) == [b])
    }

    @Test func idsComeInTheListsOrder() {
        #expect(ListSelection.several([d, a, c], anchor: d).ids(in: rows) == [a, c, d])
        #expect(ListSelection.reading(b).ids(in: rows) == [b])
        #expect(ListSelection.none.ids(in: rows) == [])
    }

    // MARK: Rows leaving

    @Test func keepingDropsGoneRowsWithoutMoving() {
        #expect(
            ListSelection.reading(b).keeping([a, c]) == .reading(b),
            "the conversation being read stays read while its row is gone, so it is marked again when it comes back")
        #expect(ListSelection.reading(b).keeping([a, b]) == .reading(b))
        // On touch Select mode stays on with one row or none.
        #expect(ListSelection.several([b, c], anchor: c).keeping([a, b]) == .several([b], anchor: nil))
        #expect(ListSelection.several([b], anchor: nil).keeping([a]) == .several([], anchor: nil))
    }
}
