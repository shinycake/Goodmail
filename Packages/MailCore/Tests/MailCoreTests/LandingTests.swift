import MailCore
import Testing

/// Where a window goes after the reader puts away the conversation they're reading: the row below, else the row
/// above, else the list (R7).
struct LandingTests {
    private static func row(_ name: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: name)
    }

    private let a = row("a"), b = row("b"), c = row("c"), d = row("d"), e = row("e")
    private var rows: [ThreadSummary.ID] { [a, b, c, d, e] }

    private func landing(
        putting putAway: Set<ThreadSummary.ID>, from anchor: ThreadSummary.ID, trail: [ThreadSummary.ID] = [],
        rows: [ThreadSummary.ID]? = nil, setting: AfterRemoval = .next
    ) -> Landing {
        Landing.after(putAway: putAway, anchor: anchor, trail: trail, rows: rows ?? self.rows, setting: setting)
    }

    @Test func theFirstOrAMiddleRowGoesToTheRowBelow() {
        #expect(landing(putting: [a], from: a) == .thread(b))
        #expect(landing(putting: [c], from: c) == .thread(d))
    }

    @Test func theLastRowGoesToTheRowAbove() {
        #expect(landing(putting: [e], from: e) == .thread(d))
    }

    @Test func theOnlyRowGoesToTheList() {
        #expect(landing(putting: [a], from: a, rows: [a]) == .list)
    }

    @Test func severalPutAwayGoToTheFirstRowBelowThatStays() {
        #expect(landing(putting: [b, c], from: b) == .thread(d))
        #expect(landing(putting: [b, d], from: b) == .thread(c))
        #expect(landing(putting: [d, e], from: d) == .thread(c), "below them is nothing left, so above")
        #expect(landing(putting: Set(rows), from: a) == .list)
    }

    @Test func aConversationTheListNeverHeldGoesToTheList() {
        #expect(landing(putting: [Self.row("from an alert")], from: Self.row("from an alert")) == .list)
    }

    @Test func oneWhoseRowLeftSinceItOpenedIsPlacedByTheTrail() {
        // Read in an Unread smart mailbox: its row left as it was read.
        #expect(landing(putting: [b], from: b, trail: rows, rows: [a, c, d, e]) == .thread(c))
        #expect(landing(putting: [e], from: e, trail: rows, rows: [a, b, c, d]) == .thread(d))
        #expect(
            landing(putting: [b], from: b, trail: rows, rows: [a, d, e]) == .thread(d),
            "rows of the trail that have left since are passed over")
        #expect(landing(putting: [b], from: b, trail: [b, c], rows: [a]) == .list, "nothing of the trail is left")
    }

    @Test func theRowsNowWinOverTheTrail() {
        // A row arrived by sync below the anchor since it opened.
        let arrived = Self.row("new")
        #expect(landing(putting: [b], from: b, trail: rows, rows: [a, b, arrived, c, d, e]) == .thread(arrived))
    }

    @Test func returningToTheListGoesThereWherever() {
        #expect(landing(putting: [b], from: b, setting: .list) == .list)
        #expect(landing(putting: [e], from: e, setting: .list) == .list)
    }
}
