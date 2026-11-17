import Testing

@testable import MailUI

@MainActor
struct SectionTitlesTests {
    private func sections(_ titles: [(MailboxSection, String)]) -> [MailboxViewModel.Section] {
        titles.map { MailboxViewModel.Section(id: $0.0, title: $0.1, threads: []) }
    }

    /// Trashing every row of a section takes the section away. The sections left keep their titles, so none of their
    /// rows are reloaded under the list's own animation.
    @Test func aSectionLeavingRetitlesNothing() {
        var titles = SectionTitles()
        _ = titles.update(to: sections([(.time(.thisEvening), "This Evening"), (.time(.yesterday), "Yesterday")]))

        let retitled = titles.update(to: sections([(.time(.yesterday), "Yesterday")]))

        #expect(retitled.isEmpty)
        #expect(titles[.time(.yesterday)] == "Yesterday")
        #expect(titles[.time(.thisEvening)] == nil)
    }

    @Test func aSectionArrivingRetitlesNothing() {
        var titles = SectionTitles()
        _ = titles.update(to: sections([(.time(.yesterday), "Yesterday")]))

        let retitled = titles.update(to: sections([(.pinned, "Pinned"), (.time(.yesterday), "Yesterday")]))

        #expect(retitled.isEmpty)
        #expect(titles[.pinned] == "Pinned")
    }

    @Test func onlyASectionWhoseTitleChangedIsRetitled() {
        var titles = SectionTitles()
        _ = titles.update(to: sections([(.time(.thisWeek), "This Week"), (.time(.lastWeek), "Last Week")]))

        let retitled = titles.update(
            to: sections([(.time(.thisWeek), "Cette semaine"), (.time(.lastWeek), "Last Week")]))

        #expect(retitled == [.time(.thisWeek)])
        #expect(titles[.time(.thisWeek)] == "Cette semaine")
    }
}
