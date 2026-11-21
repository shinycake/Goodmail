import Foundation
import MailCore
import Testing

/// What the list's filter asks for, and how choosing in its menu turns it on and off.
struct ListFilterTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "me@example.com", color: .blue, service: .gmail)

    private func thread(
        unread: Bool = false, starred: Bool = false, holdsAttachments: Bool? = nil
    ) -> MailFacts {
        let summary = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t"), subject: "Hello", snippet: "",
            sender: Contact(name: nil, address: "dana@shop.com"), date: .now, isUnread: unread, messageCount: 1,
            labelIDs: starred ? [SystemLabel.inbox, SystemLabel.starred] : [SystemLabel.inbox])
        return MailFacts(thread: summary, account: account, local: .init(holdsAttachments: holdsAttachments))
    }

    @Test func aWindowStartsUnfiltered() {
        #expect(ListFilter.none.isOn == false)
        #expect(ListFilter.none.condition == nil)
        #expect(ListFilter.none.admits(thread()))
    }

    @Test func turningItOnAsksForUnreadFirst() {
        #expect(ListFilter.none.toggled() == .on([.unread]))
    }

    @Test func turningItOffAndOnBringsBackWhatWasChosen() {
        let chosen = ListFilter.on([.starred, .withAttachments])
        let off = chosen.toggled()
        #expect(off == .off(last: [.starred, .withAttachments]))
        #expect(off.toggled() == chosen)
    }

    @Test func choosingAnOptionWhileOffTurnsItOnForThatOneAlone() {
        let filter = ListFilter.off(last: [.starred, .unread]).toggling(.withAttachments)
        #expect(filter == .on([.withAttachments]))
    }

    @Test func optionsAreCheckedAndUncheckedOneAtATime() {
        var filter = ListFilter.on([.unread])
        filter = filter.toggling(.starred)
        #expect(filter == .on([.unread, .starred]))
        #expect(filter.asks(for: .starred))
        filter = filter.toggling(.unread)
        #expect(filter == .on([.starred]))
        #expect(!filter.asks(for: .unread))
    }

    @Test func uncheckingTheLastOptionTurnsTheFilterOff() {
        let filter = ListFilter.on([.starred]).toggling(.starred)
        #expect(filter == .off(last: [.starred]))
        #expect(filter.toggled() == .on([.starred]), "the choice isn't lost")
    }

    @Test func unreadKeepsOnlyUnreadConversations() {
        let filter = ListFilter.on([.unread])
        #expect(filter.admits(thread(unread: true)))
        #expect(!filter.admits(thread(unread: false)))
    }

    @Test func starredKeepsOnlyStarredConversations() {
        let filter = ListFilter.on([.starred])
        #expect(filter.admits(thread(starred: true)))
        #expect(!filter.admits(thread()))
    }

    @Test func withAttachmentsKeepsOnlyConversationsKnownToHoldFiles() {
        let filter = ListFilter.on([.withAttachments])
        #expect(filter.admits(thread(holdsAttachments: true)))
        #expect(!filter.admits(thread(holdsAttachments: nil)), "a conversation never opened can't be known to")
    }

    @Test func severalChoicesAllHaveToHold() {
        let filter = ListFilter.on([.unread, .starred])
        #expect(filter.admits(thread(unread: true, starred: true)))
        #expect(!filter.admits(thread(unread: true)))
        #expect(!filter.admits(thread(starred: true)))
    }

    @Test func theChoicesSurviveBeingSaved() throws {
        for filter in [ListFilter.none, .on([.unread, .withAttachments]), .off(last: [.starred])] {
            let data = try JSONEncoder().encode(filter)
            #expect(try JSONDecoder().decode(ListFilter.self, from: data) == filter)
        }
    }
}
