import Foundation
import MailCore
import Testing

@testable import MailWrist

/// A tapped alert opens its conversation over the Inbox.
@MainActor
struct WristRouteTests {
    @Test func anAlertReplacesWhatWasOpen() {
        let route = WristRoute()
        let first = ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "1")
        let second = ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "2")
        route.path = [first]
        route.open(second)
        #expect(route.path == [second])
    }

    @Test func aLinkToAConversationOpensIt() {
        let route = WristRoute()
        let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "me@example.com"), threadID: "18c/2 a&b")
        route.open(WristRoute.url(opening: thread))
        #expect(route.path == [thread])
    }

    @Test func aLinkToTheInboxClosesWhatWasOpen() {
        let route = WristRoute()
        route.path = [ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "1")]
        route.open(WristRoute.url(opening: nil))
        #expect(route.path.isEmpty)
    }

    @Test(arguments: ["https://example.com", "goodmail-watch://thread?account=a", "goodmail-watch://elsewhere"])
    func aLinkItDoesntKnowChangesNothing(link: String) throws {
        let route = WristRoute()
        let open = ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "1")
        route.path = [open]
        route.open(try #require(URL(string: link)))
        #expect(route.path == [open])
    }
}
