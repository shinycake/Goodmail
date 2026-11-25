import MailCore
import Testing

@testable import MailUI

/// What an empty list shows, from what the store and the older pages say and what shows already.
struct EmptyStateTests {
    typealias State = MailboxViewController.EmptyState

    private static let noMail = State.empty(pointingTo: nil)
    private static let scene = State.inboxZero(pointing: nil)

    static let now = ContinuousClock.now

    private func next(
        rowsShown: Bool = false, _ listing: EmptyListing, showing: State?, settled: State,
        at now: ContinuousClock.Instant = Self.now
    ) -> State? {
        State.next(rowsShown: rowsShown, listing: listing, showing: showing, settled: settled, now: now)
    }

    @Test(arguments: [EmptyListing.unknown, .firstPage, .emptiedWhilePaging, .empty])
    func rowsOnScreenShowNothingElse(listing: EmptyListing) {
        #expect(next(rowsShown: true, listing, showing: nil, settled: Self.noMail) == nil)
    }

    @Test func nothingShowsBeforeTheStoreAnswers() {
        #expect(next(.unknown, showing: nil, settled: Self.noMail) == nil)
    }

    @Test func aListThatStartsEmptySpinsForItsFirstPage() {
        #expect(next(.firstPage, showing: nil, settled: Self.scene) == .loading)
    }

    @Test(arguments: [nil, State.loading])
    func anInboxJustClearedWaitsForThePageBehindTheSpinner(showing: State?) {
        #expect(next(.emptiedWhilePaging, showing: showing, settled: Self.scene) == .awaitingPage(since: Self.now))
    }

    @Test func anInboxWaitingKeepsWhenItBeganUntilTheWaitIsOver() {
        let waiting = State.awaitingPage(since: Self.now)
        let almost = Self.now + State.pageWait - .milliseconds(1)
        #expect(next(.emptiedWhilePaging, showing: waiting, settled: Self.scene, at: almost) == waiting)
        let over = Self.now + State.pageWait
        #expect(next(.emptiedWhilePaging, showing: waiting, settled: Self.scene, at: over) == Self.scene)
    }

    @Test func anInboxWaitingShowsItsSceneAsSoonAsThePageComesEmpty() {
        let waiting = State.awaitingPage(since: Self.now)
        #expect(next(.empty, showing: waiting, settled: Self.scene, at: Self.now + .milliseconds(10)) == Self.scene)
    }

    @Test func aWaitShorterThanTheEarnedWindowKeepsALateSceneEarned() {
        let took = RecentRemoval.took(at: Self.now)
        #expect(InboxZeroArrival(onScreen: true, removal: took, at: Self.now + State.pageWait) == .earned)
    }

    @Test(arguments: [nil, State.loading, .awaitingPage(since: EmptyStateTests.now)])
    func elsewhereRowsJustGoneWaitForThePageBehindTheSpinner(showing: State?) {
        #expect(next(.emptiedWhilePaging, showing: showing, settled: Self.noMail) == .loading)
        #expect(next(.emptiedWhilePaging, showing: showing, settled: .filtered(.none)) == .loading)
    }

    @Test(arguments: [State.empty(pointingTo: nil), .inboxZero(pointing: nil), .filtered(.on([.unread]))])
    func anEmptyStateAlreadyUpStaysWhileAnotherPageComes(showing: State) {
        #expect(next(.emptiedWhilePaging, showing: showing, settled: Self.noMail) == Self.noMail)
        #expect(next(.emptiedWhilePaging, showing: showing, settled: Self.scene) == Self.scene)
    }

    @Test func nothingMoreComingShowsWhatTheMailboxShowsEmpty() {
        #expect(next(.empty, showing: .loading, settled: Self.noMail) == Self.noMail)
    }
}
