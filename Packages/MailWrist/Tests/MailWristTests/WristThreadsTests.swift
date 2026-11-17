import MailCore
import Testing

@testable import MailWrist

/// Opening a conversation on the watch asks the iPhone for it, and shows what came back or why nothing did.
@MainActor
struct WristThreadsTests {
    private let id = ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t")
    private var thread: WristThread {
        WristThread(id: id, subject: "Lunch", bubbles: [], earlier: 0, isGroup: false, code: nil)
    }

    /// Patience that runs out at once.
    private static let impatient: @Sendable () async throws -> Void = {}

    @Test func loadingAsksTheIPhoneAndWaits() async {
        let threads = WristThreads(patience: { throw CancellationError() })
        await threads.load(id)
        #expect(threads.state(of: id) == .loading, "A cancelled wait leaves the answer to come")
        var requests = threads.requests.makeAsyncIterator()
        #expect(await requests.next() == id)
    }

    @Test func showsTheReply() async {
        let threads = WristThreads(patience: { throw CancellationError() })
        await threads.load(id)
        threads.receive(.thread(thread))
        #expect(threads.state(of: id) == .loaded(thread))
        threads.receive(.gone(id))
        #expect(threads.state(of: id) == .gone)
    }

    @Test func noAnswerInTimeMeansThePhoneIsAway() async {
        let threads = WristThreads(patience: Self.impatient)
        await threads.load(id)
        #expect(threads.state(of: id) == .phoneAway)
    }

    @Test func tryingAgainAsksAgainAndWaitsAgain() async {
        let threads = WristThreads(patience: Self.impatient)
        await threads.load(id)
        var requests = threads.requests.makeAsyncIterator()
        #expect(await requests.next() == id)

        threads.phoneIsAway(id)
        await threads.load(id)
        #expect(await requests.next() == id, "Try Again sends a new request")
        #expect(threads.state(of: id) == .phoneAway, "and gives up again when it goes unanswered")
    }

    @Test func anUnreachablePhoneIsAwayAtOnce() async {
        let threads = WristThreads(patience: { throw CancellationError() })
        await threads.load(id)
        threads.phoneIsAway(id)
        #expect(threads.state(of: id) == .phoneAway)
    }

    @Test func aLoadedConversationStaysWhileItReloads() async {
        let threads = WristThreads(patience: Self.impatient)
        threads.receive(.thread(thread))
        await threads.load(id)
        #expect(threads.state(of: id) == .loaded(thread))
    }
}
