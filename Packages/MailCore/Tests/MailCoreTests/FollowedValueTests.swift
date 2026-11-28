import Synchronization
import Testing

@testable import MailCore

/// A followed value takes what its stream gives, never going back, and a write waits until the value is as new as it.
@Suite(.timeLimit(.minutes(1)))
struct FollowedValueTests {
    private struct Stored: Revised, Equatable {
        let revision: Int
    }

    /// The streams a followed value follows, one after another, handed to the test as each starts.
    private final class Source: Sendable {
        typealias Stream = AsyncThrowingStream<Stored, any Error>
        let started: AsyncStream<Stream.Continuation>
        private let starts: AsyncStream<Stream.Continuation>.Continuation
        /// What a wait reads when the following failed.
        let stored = Mutex(Stored(revision: 0))

        init() {
            (started, starts) = AsyncStream.makeStream()
        }

        func follow() -> Stream {
            let (stream, continuation) = Stream.makeStream()
            starts.yield(continuation)
            return stream
        }

        func followed(
            from initial: Stored, log: MailLog = MailLog(category: "test", sink: { _ in })
        ) -> FollowedValue<Stored> {
            FollowedValue(
                initial, following: follow, reading: { self.stored.withLock { $0 } }, againAfter: .milliseconds(1),
                atMost: .milliseconds(4), log: log)
        }
    }

    private struct Failure: Error {}

    /// Lets `followed` take what was yielded so far: a wait for `revision` ends once it has.
    private func taken(_ revision: Int, by followed: FollowedValue<Stored>) async {
        #expect(await followed.wait(forRevision: revision))
    }

    /// Returns once `count` callers wait on `followed`.
    private func waiting(_ count: Int, on followed: FollowedValue<Stored>) async {
        while followed.waiting < count { await Task.yield() }
    }

    @Test func theNewestValueGivenIsTheLatest() async {
        let source = Source()
        let followed = source.followed(from: Stored(revision: 0))
        var starts = source.started.makeAsyncIterator()
        let stream = await starts.next()
        stream?.yield(Stored(revision: 1))
        stream?.yield(Stored(revision: 2))
        await taken(2, by: followed)
        #expect(followed.latest == Stored(revision: 2))
    }

    @Test func aWaitAlreadyMetEndsAtOnce() async {
        let followed = Source().followed(from: Stored(revision: 5))
        #expect(await followed.wait(forRevision: 5))
        #expect(await followed.wait(forRevision: 3))
    }

    @Test func aWaitKeepsWaitingThroughOlderValuesAndEndsWithTheFirstAsNew() async {
        let source = Source()
        let followed = source.followed(from: Stored(revision: 0))
        var starts = source.started.makeAsyncIterator()
        let stream = await starts.next()
        let waitingForTwo = Task { await followed.wait(forRevision: 2) }
        await waiting(1, on: followed)
        stream?.yield(Stored(revision: 1))
        await taken(1, by: followed)
        #expect(followed.waiting == 1, "revision 1 doesn't show a write at revision 2")
        stream?.yield(Stored(revision: 3))
        #expect(await waitingForTwo.value)
        #expect(followed.waiting == 0)
    }

    @Test func anOlderValueNeverReplacesANewerOne() async {
        let source = Source()
        let followed = source.followed(from: Stored(revision: 4))
        var starts = source.started.makeAsyncIterator()
        let stream = await starts.next()
        stream?.yield(Stored(revision: 2))
        stream?.yield(Stored(revision: 6))
        await taken(6, by: followed)
        stream?.yield(Stored(revision: 5))
        stream?.yield(Stored(revision: 7))
        await taken(7, by: followed)
        #expect(followed.latest == Stored(revision: 7))
    }

    @Test func aCancelledWaitGoesUnmetAndStopsWaiting() async {
        let source = Source()
        let followed = source.followed(from: Stored(revision: 0))
        var starts = source.started.makeAsyncIterator()
        let stream = await starts.next()
        let cancelled = Task { await followed.wait(forRevision: 9) }
        await waiting(1, on: followed)
        cancelled.cancel()
        #expect(await cancelled.value == false)
        #expect(followed.waiting == 0, "the cancelled wait is gone")
        let other = Task { await followed.wait(forRevision: 9) }
        stream?.yield(Stored(revision: 9))
        #expect(await other.value)
    }

    @Test func aWaitReadsOnceWhenTheFollowingFailsAndTheFollowingStartsAgain() async {
        let source = Source()
        let followed = source.followed(from: Stored(revision: 0))
        var starts = source.started.makeAsyncIterator()
        let first = await starts.next()
        let waiting = Task { await followed.wait(forRevision: 3) }
        await self.waiting(1, on: followed)
        source.stored.withLock { $0 = Stored(revision: 3) }
        first?.finish(throwing: Failure())
        #expect(await waiting.value, "the read shows the write")
        #expect(followed.latest == Stored(revision: 3))
        let again = await starts.next()
        again?.yield(Stored(revision: 4))
        await taken(4, by: followed)
    }

    @Test func aWaitWhoseReadIsOlderGoesUnmet() async {
        let source = Source()
        let followed = source.followed(from: Stored(revision: 0))
        var starts = source.started.makeAsyncIterator()
        let first = await starts.next()
        let waiting = Task { await followed.wait(forRevision: 3) }
        await self.waiting(1, on: followed)
        first?.finish(throwing: Failure())
        #expect(await waiting.value == false)
    }

    @Test func failuresInARowAreLoggedOnceUntilAValueComes() async {
        let source = Source()
        let logged = Mutex(0)
        let followed = source.followed(
            from: Stored(revision: 0), log: MailLog(category: "test", sink: { _ in logged.withLock { $0 += 1 } }))
        var starts = source.started.makeAsyncIterator()
        await starts.next()?.finish(throwing: Failure())
        await starts.next()?.finish(throwing: Failure())
        let third = await starts.next()
        #expect(logged.withLock { $0 } == 1)
        third?.yield(Stored(revision: 1))
        await taken(1, by: followed)
        third?.finish(throwing: Failure())
        _ = await starts.next()
        #expect(logged.withLock { $0 } == 2, "a value came between")
    }

    @Test func releasingTheValueStopsTheFollowing() async {
        let source = Source()
        var followed: FollowedValue<Stored>? = source.followed(from: Stored(revision: 0))
        var starts = source.started.makeAsyncIterator()
        let stream = await starts.next()
        let (stopped, stop) = AsyncStream<Void>.makeStream()
        stream?.onTermination = { _ in stop.finish() }
        #expect(followed?.latest == Stored(revision: 0))
        followed = nil
        for await _ in stopped {}
    }
}
