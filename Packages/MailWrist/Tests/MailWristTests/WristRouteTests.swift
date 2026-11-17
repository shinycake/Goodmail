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
}
