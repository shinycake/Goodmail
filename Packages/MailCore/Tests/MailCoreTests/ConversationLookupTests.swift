import Foundation
import MailCore
import Synchronization
import Testing

/// A conversation not on the device is asked of its service once and stored as sync stores it; only the service saying
/// it doesn't exist makes it gone, not failing to reach the service (R10).
struct ConversationLookupTests {
    private let thread = navigationRow("b")

    /// What the lookup wrote to the store.
    private final class Written: Sendable {
        let changes = Mutex<[StoreChanges]>([])
    }

    private func lookup(
        stored: ThreadSummary? = nil, fetch: @escaping ConversationLookup.Fetch, written: Written = Written(),
        storeFails: Bool = false
    ) -> ConversationLookup {
        ConversationLookup(
            stored: { _ in stored }, fetch: fetch,
            store: { changes in
                if storeFails { throw URLError(.cannotWriteToFile) }
                written.changes.withLock { $0.append(changes) }
            })
    }

    @Test func oneOnTheDeviceIsFoundWithoutAskingTheService() async {
        let found = await lookup(
            stored: thread,
            fetch: { _ in
                Issue.record("asked the service")
                return nil
            }
        )
        .find(thread.id)
        #expect(found == .found(thread))
    }

    @Test func oneTheServiceHasIsStoredThenFound() async {
        let written = Written()
        let row = thread
        let found = await lookup(fetch: { _ in ThreadFetch(found: [row], missing: []) }, written: written)
            .find(thread.id)
        #expect(found == .found(thread))
        let stored = written.changes.withLock { $0 }
        #expect(stored.map(\.upserts) == [[thread]], "its row is stored, so its messages have one to belong to")
        #expect(stored.first?.accountID == thread.id.accountID)
    }

    @Test func oneTheServiceSaysIsMissingIsGone() async {
        let written = Written()
        let id = thread.id.threadID
        let found = await lookup(fetch: { _ in ThreadFetch(found: [], missing: [id]) }, written: written)
            .find(thread.id)
        #expect(found == .gone)
        #expect(written.changes.withLock { $0.map(\.deletions) } == [[id]], "stored as gone too")
    }

    @Test func oneTheServiceDoesntKnowIsGone() async {
        #expect(await lookup(fetch: { _ in throw ProviderError.notFound }).find(thread.id) == .gone)
    }

    @Test func oneWhoseAccountIsGoneIsGone() async {
        #expect(await lookup(fetch: { _ in nil }).find(thread.id) == .gone)
    }

    @Test func oneTheServiceCantBeAskedAboutIsUnreachable() async {
        #expect(await lookup(fetch: { _ in throw URLError(.notConnectedToInternet) }).find(thread.id) == .unreachable)
    }

    @Test func oneThatCantBeStoredIsUnreachable() async {
        let row = thread
        let found = await lookup(fetch: { _ in ThreadFetch(found: [row], missing: []) }, storeFails: true)
            .find(thread.id)
        #expect(found == .unreachable, "a reader with no stored row couldn't show its messages")
    }
}
