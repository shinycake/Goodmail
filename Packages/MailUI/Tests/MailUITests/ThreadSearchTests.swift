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
            remote: { text in
                asked.append(text)
                return [ThreadSummary.ID(accountID: account, threadID: "server")]
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
            remote: { _ in
                asked += 1
                return []
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
        let search = ThreadSearch(local: local, remote: { _ in throw Offline() }, pause: .seconds(60))
        _ = search.results()
        search.update("invoice")
        await #expect(throws: Offline.self) { try await search.refresh() }
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
