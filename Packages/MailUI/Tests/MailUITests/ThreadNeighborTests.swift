import Foundation
import MailCore
import Testing

@testable import MailUI

/// Next and Previous Message walk the list as it shows.
@MainActor @Suite("Next and previous message")
struct ThreadNeighborTests {
    @Test func stepsThroughTheListAndStopsAtItsEnds() async {
        let account = AccountID(rawValue: "a")
        let ids = (0..<3).map { ThreadSummary.ID(accountID: account, threadID: "t\($0)") }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let threads = ids.enumerated().map { index, id in
            ThreadSummary(
                id: id, subject: "s", snippet: "", sender: Contact(name: nil, address: "x@example.com"),
                date: now - Double(index) * 60, isUnread: false, messageCount: 1, labelIDs: ["INBOX"])
        }
        let list = MailboxViewModel(
            accounts: [],
            source: .flat {
                AsyncThrowingStream {
                    $0.yield(threads)
                    $0.finish()
                }
            }, refresh: {},
            now: { now })
        await list.observe()
        #expect(list.thread(1, from: nil) == ids[0])
        #expect(list.thread(-1, from: nil) == nil)
        #expect(list.thread(1, from: ids[0]) == ids[1])
        #expect(list.thread(-1, from: ids[1]) == ids[0])
        #expect(list.thread(1, from: ids[2]) == nil)
    }
}
