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
        dock.show(2)
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
        dock.show(4)
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
        dock.show(1)
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
