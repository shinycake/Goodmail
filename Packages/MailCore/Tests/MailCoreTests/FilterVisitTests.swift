import MailCore
import Testing

/// A filtered list keeps what was read on this visit while the filter stays, as Mail does, and starts over when the
/// filter or the list changes.
struct FilterVisitTests {
    private let a = navigationRow("a").id, b = navigationRow("b").id

    @Test func whatWasReadHereStaysWhileTheFilterDoes() {
        var visit = FilterVisit(.on([.unread]))
        #expect(!visit.shows(a) { false })
        visit.read(a)
        #expect(visit.shows(a) { false })
        #expect(visit.shows(b) { true }, "what the filter admits shows")
        #expect(!visit.shows(b) { false })
    }

    @Test func aNewFilterOrListStartsOverKeepingOnlyTheOneRead() {
        var visit = FilterVisit(.on([.unread]))
        visit.read(a)
        visit.read(b)
        visit.filter(by: .on([.unread]), reading: nil)
        #expect(visit.shows(a) { false }, "the same filter keeps the visit")
        visit.filter(by: .on([.starred]), reading: b)
        #expect(!visit.shows(a) { false })
        #expect(visit.shows(b) { false }, "the one read doesn't leave from under the reader")
        visit.restart(reading: nil)
        #expect(!visit.shows(b) { false })
    }

    @Test func withTheFilterOffEverythingShowsAndNothingIsKept() {
        var visit = FilterVisit(.none)
        visit.read(a)
        #expect(visit.shows(a) { false })
        visit.filter(by: .on([.unread]), reading: nil)
        #expect(!visit.shows(a) { false }, "read while off isn't kept")
    }
}
