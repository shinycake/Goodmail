import MailCore
import Testing
import UIKit

@testable import MailUI

/// A screen that says whether the pill's place shows, and counts how often the pill changed.
@MainActor
private final class StubSite: DraftsPillSite {
    var showsDraftsPill: Bool
    private(set) var changes = 0

    init(shows: Bool = true) {
        showsDraftsPill = shows
    }

    func draftsPillDidChange() {
        changes += 1
    }
}

@MainActor
@Suite("Drafts pill")
struct DraftsPillTests {
    private func button(of pill: DraftsPillItem) throws -> UIButton {
        try #require(pill.item.customView as? UIButton)
    }

    /// `subjects.count` minimized drafts with those subjects.
    private func drafts(_ subjects: String...) -> [Draft] {
        subjects.map { Draft(accountID: AccountID(rawValue: "a"), subject: $0) }
    }

    @Test("A new pill is hidden")
    func startsHidden() {
        let site = StubSite()
        let pill = DraftsPillItem(site: site) {}
        #expect(pill.item.isHidden)
        #expect(pill.count == 0)
    }

    @Test("One draft shows the pill with its count, label and hint")
    func showsOne() throws {
        let site = StubSite()
        let pill = DraftsPillItem(site: site) {}
        pill.show(1)
        let button = try button(of: pill)
        #expect(!pill.item.isHidden)
        #expect(button.configuration?.title == "1")
        #expect(button.accessibilityLabel == "1 Draft")
        #expect(button.accessibilityHint == "Opens the message.")
        #expect(button.accessibilityIdentifier == "drafts.pill")
    }

    @Test("VoiceOver reads the only draft's title as the pill's value, and none for several")
    func readsTheOnlyTitle() throws {
        let dock = DraftsDock()
        let pill = dock.makePill(for: StubSite())
        let button = try button(of: pill)
        dock.show(drafts("Lunch"))
        #expect(button.accessibilityValue == "Lunch")
        dock.show(drafts("Budget"))
        #expect(button.accessibilityValue == "Budget")
        dock.show(drafts("Lunch", "Budget"))
        #expect(button.accessibilityValue == nil)
        dock.show(drafts(""))
        #expect(button.accessibilityValue == "New Message")
    }

    @Test("A new title alone doesn't lay the toolbar out again")
    func titleAloneKeepsLayout() {
        let dock = DraftsDock()
        let site = StubSite()
        let pill = dock.makePill(for: site)
        dock.show(drafts("Lunch"))
        dock.show(drafts("Budget"))
        #expect(site.changes == 1)
        withExtendedLifetime(pill) {}
    }

    @Test("Several drafts say how many and offer to pick one")
    func showsSeveral() throws {
        let site = StubSite()
        let pill = DraftsPillItem(site: site) {}
        pill.show(3)
        let button = try button(of: pill)
        #expect(button.configuration?.title == "3")
        #expect(button.accessibilityLabel == "3 Drafts")
        #expect(button.accessibilityHint == "Shows the drafts to pick one.")
    }

    @Test("None hides the pill again")
    func showsNone() {
        let site = StubSite()
        let pill = DraftsPillItem(site: site) {}
        pill.show(2)
        pill.show(0)
        #expect(pill.item.isHidden)
    }

    @Test("Only a change tells the screen")
    func changesOnce() {
        let site = StubSite()
        let pill = DraftsPillItem(site: site) {}
        pill.show(1)
        pill.show(1)
        #expect(site.changes == 1)
        pill.show(2)
        #expect(site.changes == 2)
    }

    @Test("A pill made after the dock has drafts shows them")
    func madeLater() {
        let dock = DraftsDock()
        dock.show(drafts("a", "b"))
        let site = StubSite()
        let pill = dock.makePill(for: site)
        #expect(pill.count == 2)
        #expect(!pill.item.isHidden)
    }

    @Test("The dock's count reaches every live pill")
    func reachesEveryPill() {
        let dock = DraftsDock()
        let sites = [StubSite(), StubSite()]
        let pills = sites.map { dock.makePill(for: $0) }
        dock.show(drafts("a", "b", "c", "d"))
        #expect(pills.map(\.count) == [4, 4])
    }

    @Test("A released pill is dropped, and the others still hear the count")
    func dropsReleasedPills() {
        let dock = DraftsDock()
        let site = StubSite()
        weak var released: DraftsPillItem?
        do {
            let pill = dock.makePill(for: site)
            released = pill
        }
        #expect(released == nil)
        let kept = dock.makePill(for: site)
        dock.show(drafts("a"))
        #expect(kept.count == 1)
        #expect(dock.shownPill === kept)
    }

    @Test("The shown pill is the one whose screen shows it")
    func shownPill() {
        let dock = DraftsDock()
        let hidden = StubSite(shows: false)
        let showing = StubSite(shows: true)
        _ = dock.makePill(for: hidden)
        let pill = dock.makePill(for: showing)
        let other = dock.makePill(for: hidden)
        #expect(dock.shownPill === pill)
        showing.showsDraftsPill = false
        #expect(dock.shownPill == nil)
        withExtendedLifetime(other) {}
    }

    @Test("A card setting off for the pill shows one more on every pill, and unhides one at none")
    func expects() {
        let dock = DraftsDock()
        let pills = [dock.makePill(for: StubSite()), dock.makePill(for: StubSite())]
        dock.expect()
        #expect(pills.map(\.count) == [1, 1])
        #expect(pills.allSatisfy { !$0.item.isHidden })
        dock.show(drafts("a"))
        #expect(pills.map(\.count) == [2, 2], "the shelf's change still counts the card coming")
    }

    @Test("A card that comes back puts the pills back")
    func turnsAway() {
        let dock = DraftsDock()
        let pill = dock.makePill(for: StubSite())
        dock.show(drafts("a"))
        dock.expect()
        dock.turnAway()
        #expect(pill.count == 1)
        dock.show(drafts())
        dock.expect()
        dock.turnAway()
        #expect(pill.item.isHidden)
    }

    @Test("A card landing as its message is minimized leaves the pill as it was")
    func landsMinimized() {
        let dock = DraftsDock()
        let site = StubSite()
        let pill = dock.makePill(for: site)
        dock.show(drafts("a"))
        dock.expect()
        let changes = site.changes
        dock.land { dock.show(drafts("a", "b")) }
        #expect(pill.count == 2)
        #expect(site.changes == changes, "nothing to lay out again")
    }

    @Test("A card landing that minimizes nothing drops the one it was counted as")
    func landsEmpty() {
        let dock = DraftsDock()
        let pill = dock.makePill(for: StubSite())
        dock.show(drafts("a"))
        dock.expect()
        dock.land {}
        #expect(pill.count == 1)
    }

    @Test(
        "A card can't be received by a pill that isn't on show or placed, and nothing is counted",
        arguments: [false, true])
    func receivesNowhere(shows: Bool) {
        let dock = DraftsDock()
        let pill = dock.makePill(for: StubSite(shows: shows))
        dock.show(drafts("a"))
        #expect(dock.receive(in: UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))) == nil)
        #expect(pill.count == 1)
    }

    @Test("Turning away when nothing was expected changes nothing")
    func turnsAwayIdle() {
        let dock = DraftsDock()
        let site = StubSite()
        let pill = dock.makePill(for: site)
        dock.show(drafts("a"))
        dock.turnAway()
        #expect(pill.count == 1)
        #expect(site.changes == 1)
    }

    @Test("A long press on the pill offers Dismiss All, which reaches the dock with the pill")
    func dismissAll() throws {
        let dock = DraftsDock()
        var source: UIView?
        dock.onDismissAll = { source = $0 }
        let pill = dock.makePill(for: StubSite())
        let button = try button(of: pill)
        let action = try #require(button.menu?.children.first as? UIAction)
        #expect(action.title == "Dismiss All")
        action.performWithSender(nil, target: nil)
        #expect(source === button)
    }

    @Test(
        "Dismissing says how many it deletes or saves",
        arguments: [
            (DraftDismissal.delete, 1, "Delete Draft"), (.delete, 3, "Delete 3 Drafts"), (.save, 1, "Save Draft"),
            (.save, 2, "Save 2 Drafts"),
        ])
    func dismissalTitles(dismissal: DraftDismissal, count: Int, title: String) {
        #expect(dismissal.title(count: count) == title)
    }

    @Test("Tapping the pill reaches the dock")
    func tapOpens() throws {
        let dock = DraftsDock()
        var opened = 0
        dock.onOpen = { opened += 1 }
        let site = StubSite()
        let pill = dock.makePill(for: site)
        try button(of: pill).sendActions(for: .primaryActionTriggered)
        #expect(opened == 1)
    }
}
