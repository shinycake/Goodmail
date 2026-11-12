import Foundation
import MailCore
import Testing

@testable import MailUI

/// Search as the user types: the store's answer at once, the provider's merged in after a pause.
@MainActor
struct ThreadSearchTests {
    private let account = AccountID(rawValue: "a")

    private func thread(_ id: String) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account, threadID: id), subject: id, snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: false, messageCount: 1,
            labelIDs: ["INBOX"])
    }

    /// A store whose "matches" for some text are the text's words, plus the provider's IDs.
    private func local(_ text: String, _ ids: [ThreadSummary.ID]) -> AsyncThrowingStream<[ThreadSummary], any Error> {
        let words = text.split(separator: " ").map { thread(String($0)) }
        let threads = words + ids.map { thread($0.threadID) }
        return AsyncThrowingStream { continuation in continuation.yield(threads) }
    }

    @Test func showsLocalMatchesAtOnceThenTheProvidersAfterAPause() async throws {
        var asked: [String] = []
        let search = ThreadSearch(
            local: local,
            remote: { text, _ in
                asked.append(text)
                return SearchPage(ids: [ThreadSummary.ID(accountID: account, threadID: "server")])
            },
            pause: .milliseconds(50))
        var results = search.results().makeAsyncIterator()
        #expect(try await results.next()?.map(\.id.threadID) == [])

        search.update("in")
        search.update("invoice")
        #expect(try await results.next()?.map(\.id.threadID) == ["invoice"], "typing on replaces the last answer")
        #expect(try await results.next()?.map(\.id.threadID) == ["invoice", "server"])
        #expect(asked == ["invoice"], "the provider is asked once typing pauses")
    }

    @Test func blankTextNeverReachesTheProvider() async throws {
        var asked = 0
        let search = ThreadSearch(
            local: local,
            remote: { _, _ in
                asked += 1
                return SearchPage()
            },
            pause: .zero)
        _ = search.results()
        search.update("   ")
        try await search.refresh()
        try await Task.sleep(for: .milliseconds(50))
        #expect(asked == 0)
    }

    @Test func refreshAsksTheProviderAndKeepsItsFailure() async throws {
        struct Offline: Error {}
        let search = ThreadSearch(local: local, remote: { _, _ in throw Offline() }, pause: .seconds(60))
        _ = search.results()
        search.update("invoice")
        await #expect(throws: Offline.self) { try await search.refresh() }
    }

    /// A provider whose matches for any text are `matches`, two to a page, the token being where the next starts.
    /// Records each page asked for.
    private final class PagedProvider {
        let matches: [String]
        var asked: [String?] = []
        /// Runs as a page after the first is asked for, before it is answered.
        var onNextPage: () -> Void = {}

        init(_ matches: [String]) { self.matches = matches }

        func page(_ text: String, after page: SearchPage?) -> SearchPage {
            let token = page?.next.values.first
            asked.append(token)
            if token != nil { onNextPage() }
            let start = token.flatMap(Int.init) ?? 0
            let end = min(start + 2, matches.count)
            let account = AccountID(rawValue: "a")
            return SearchPage(
                ids: matches[start..<end].map { ThreadSummary.ID(accountID: account, threadID: $0) },
                next: end < matches.count ? [account: String(end)] : [:])
        }
    }

    /// The provider matches the store was last asked to include.
    private final class Included {
        var ids: [String] = []
    }

    private func makeSearch(_ provider: PagedProvider, included: Included) -> ThreadSearch {
        ThreadSearch(
            local: { text, ids in
                included.ids = ids.map(\.threadID)
                return self.local(text, ids)
            },
            remote: { provider.page($0, after: $1) },
            pause: .seconds(60))
    }

    @Test func loadMoreAddsTheProvidersNextPagesUntilTheyRunOut() async throws {
        let provider = PagedProvider(["s1", "s2", "s3", "s4", "s5"])
        let included = Included()
        let search = makeSearch(provider, included: included)
        _ = search.results()
        search.update("invoice")
        try await search.loadMore()
        #expect(provider.asked.isEmpty, "before the first page there is nothing to go on from")

        try await search.refresh()
        #expect(included.ids == ["s1", "s2"])
        try await search.loadMore()
        #expect(included.ids == ["s1", "s2", "s3", "s4"])
        try await search.loadMore()
        try await search.loadMore()
        #expect(included.ids == ["s1", "s2", "s3", "s4", "s5"])
        #expect(provider.asked == [nil, "2", "4"], "the last page ends the asking")

        try await search.refresh()
        #expect(included.ids == ["s1", "s2"], "a refresh starts the pages over")
    }

    @Test func aPageForTextNoLongerSearchedIsDropped() async throws {
        let provider = PagedProvider(["s1", "s2", "s3"])
        let included = Included()
        let search = makeSearch(provider, included: included)
        provider.onNextPage = { search.update("other") }
        _ = search.results()
        search.update("invoice")
        try await search.refresh()
        try await search.loadMore()
        #expect(included.ids == [], "the late page doesn't join the new text's results")
        try await search.loadMore()
        #expect(provider.asked == [nil, "2"], "the new text has no pages yet")
    }
}

@MainActor
struct RecentSearchesTests {
    private let defaults = UserDefaults(suiteName: "RecentSearchesTests-\(UUID().uuidString)")!

    @Test func newestFirstOnceEachAndCapped() {
        let recents = RecentSearches(defaults: defaults)
        recents.record("  invoice ")
        recents.record("dana")
        recents.record("Invoice")
        recents.record("   ")
        #expect(recents.all == ["Invoice", "dana"])
        for index in 0..<10 { recents.record("q\(index)") }
        #expect(recents.all.count == RecentSearches.limit)
        #expect(recents.all.first == "q9")
        recents.clear()
        #expect(recents.all.isEmpty)
    }
}
