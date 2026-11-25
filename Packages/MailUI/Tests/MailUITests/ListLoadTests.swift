import Foundation
import MailCore
import Testing

@testable import MailUI

/// What an empty list means while the store answers and older pages come: a list that starts empty waits for its first
/// page, and one the reader emptied is empty at once, whatever is still being fetched.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ListLoadTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)

    private func thread(_ id: String) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: Date(timeIntervalSince1970: 1_800_000_000),
            isUnread: false, messageCount: 1, labelIDs: [SystemLabel.inbox])
    }

    /// Holds every older page back until it opens.
    private final class Gate {
        private let stream: AsyncStream<Void>
        private let opener: AsyncStream<Void>.Continuation
        var fetches = 0

        init() {
            (stream, opener) = AsyncStream<Void>.makeStream()
        }

        func page() async -> Bool {
            fetches += 1
            for await _ in stream {}
            return false
        }

        func open() { opener.finish() }
    }

    private func list(_ gate: Gate) -> (MailboxViewModel, AsyncThrowingStream<[ThreadSummary], any Error>.Continuation)
    {
        let (stream, feed) = AsyncThrowingStream<[ThreadSummary], any Error>.makeStream()
        let list = MailboxViewModel(
            accounts: [account], source: .flat { stream }, refresh: {}, older: .pages { await gate.page() })
        return (list, feed)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
        #expect(condition())
    }

    @Test func aListThatStartsEmptyWaitsForItsFirstPageFromTheMoment() async {
        let gate = Gate()
        let (list, feed) = list(gate)
        let observing = Task { await list.observe() }
        #expect(list.emptyListing == .unknown, "the store hasn't answered")
        feed.yield([])
        await waitUntil { list.listing.hasAnswered }
        #expect(list.emptyListing == .firstPage, "the fetch starts with the answer, not after it")
        gate.open()
        await waitUntil { list.older == .exhausted }
        #expect(list.emptyListing == .empty)
        feed.finish()
        await observing.value
    }

    @Test func aListWhoseThreadsWentSaysAPageIsOnItsWay() async {
        let gate = Gate()
        let (list, feed) = list(gate)
        let observing = Task { await list.observe() }
        feed.yield([thread("a")])
        await waitUntil { list.rows.count == 1 }
        feed.yield([])
        await waitUntil { list.rows.isEmpty }
        #expect(gate.fetches == 1)
        #expect(list.emptyListing == .emptiedWhilePaging, "the page may bring mail back")
        gate.open()
        await waitUntil { list.older == .exhausted }
        #expect(list.emptyListing == .empty)
        feed.finish()
        await observing.value
    }

    @Test func aSecondAskJoinsThePageOnItsWay() async {
        let gate = Gate()
        let (list, _) = list(gate)
        let first = list.loadOlder()
        #expect(list.loadOlder() == first)
        gate.open()
        await list.loadOlderIfNeeded()
        #expect(gate.fetches == 1)
        #expect(list.loadOlder() == nil, "the provider has no more")
    }

    @Test func pagesOwnedByASearchAreAskedForEachTime() async {
        var more = false
        var fetches = 0
        let list = MailboxViewModel(
            accounts: [account], source: .flat { AsyncThrowingStream { $0.finish() } }, refresh: {},
            older: .owned(hasMore: { more }, fetch: { fetches += 1 }))
        #expect(list.loadOlder() == nil, "nothing to fetch for this text")
        more = true
        await list.loadOlderIfNeeded()
        await list.loadOlderIfNeeded()
        #expect(fetches == 2, "the search's answer is never kept")
        #expect(list.older == .mayHaveMore)
    }

    @Test func switchingCategoryWaitsForTheCategorysThreads() async {
        let list = MailboxViewModel(
            accounts: [account],
            source: .categorised(
                InboxCategories(
                    threads: { [thread] category in
                        AsyncThrowingStream { $0.yield(category == .primary ? [thread("p")] : []) }
                    },
                    unreadCounts: { AsyncThrowingStream { $0.yield([:]) } }),
                selected: .primary),
            refresh: {})
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.listing == .listed([thread("p")]) }
        list.select(.social)
        #expect(
            list.listing == .waiting(showing: [thread("p")]),
            "Primary's threads stay until Social's come, so the switch is one change, but say nothing of Social's")
        #expect(list.rows.map(\.threadID) == ["p"])
        #expect(list.emptyListing == .unknown)
        await waitUntil { list.listing == .empty }
    }

    @Test func aCategoryNeverWaitsOnTheInboxsPages() async {
        let gate = Gate()
        let list = MailboxViewModel(
            accounts: [account],
            source: .categorised(
                InboxCategories(
                    threads: { _ in AsyncThrowingStream { $0.yield([]) } },
                    unreadCounts: { AsyncThrowingStream { $0.yield([:]) } }),
                selected: .primary),
            refresh: {}, older: .pages { await gate.page() })
        let observing = Task { await list.observe() }
        defer { observing.cancel() }
        await waitUntil { list.listing == .empty }
        list.loadOlder()
        #expect(list.emptyListing == .empty, "a page of the whole Inbox may bring nothing to this category")
        gate.open()
    }

    @Test func aShortListAsksAgainWhileEachPageGrowsIt() async {
        var pages = 0
        let (stream, feed) = AsyncThrowingStream<[ThreadSummary], any Error>.makeStream()
        let list = MailboxViewModel(
            accounts: [account], source: .flat { stream }, refresh: {},
            older: .pages { [thread] in
                pages += 1
                // The store answers with the page's threads before the fetch hears back.
                feed.yield((0...pages).map { thread("\($0)") })
                return pages < 3
            })
        let observing = Task { await list.observe() }
        feed.yield([thread("0")])
        await waitUntil { list.older == .exhausted }
        #expect(pages == 3, "each page that says there is more is followed by the next while the list is short")
        feed.finish()
        await observing.value
    }

    @Test func aPageThatAddsNothingHereStopsTheAsking() async {
        var pages = 0
        let (stream, feed) = AsyncThrowingStream<[ThreadSummary], any Error>.makeStream()
        let list = MailboxViewModel(
            accounts: [account], source: .flat { stream }, refresh: {},
            older: .pages {
                pages += 1
                return true
            })
        let observing = Task { await list.observe() }
        // Its threads never show here, as when an archive still in the outbox takes them away again.
        feed.yield([thread("a")])
        await waitUntil { list.older == .mayHaveMore && pages == 1 }
        feed.yield([thread("a")])
        for _ in 0..<100 { await Task.yield() }
        #expect(pages == 1, "neither the page nor the store's answer that changes nothing asks again")
        feed.finish()
        await observing.value
    }
}
