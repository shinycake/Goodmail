import MailCore
import Testing

/// Work started from synchronous code runs as children of one owner, and ends with it.
@Suite(.timeLimit(.minutes(1)))
struct ErrandsTests {
    private enum Event: Equatable {
        case started
        case ended(cancelled: Bool)
    }

    /// Starts an errand that waits until it is cancelled, and returns once it is under way, with what it reports.
    private func startWaiting(on errands: Errands) async -> AsyncStream<Event>.Iterator {
        let (events, report) = AsyncStream.makeStream(of: Event.self)
        errands.start {
            report.yield(.started)
            try? await Task.sleep(for: .seconds(3600))
            report.yield(.ended(cancelled: Task.isCancelled))
        }
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .started)
        return iterator
    }

    @Test func startedErrandsRunSideBySide() async {
        let errands = Errands()
        let (ran, report) = AsyncStream.makeStream(of: Int.self)
        let (opened, open) = AsyncStream.makeStream(of: Void.self)
        // The first waits for the last, so they can only finish if they run at once.
        errands.start {
            for await _ in opened { break }
            report.yield(1)
        }
        errands.start { report.yield(2) }
        errands.start {
            open.yield()
            report.yield(3)
        }
        var seen: Set<Int> = []
        for await errand in ran {
            seen.insert(errand)
            if seen.count == 3 { break }
        }
        #expect(seen == [1, 2, 3])
    }

    @Test func cancellingStopsTheErrandsUnderWay() async {
        let errands = Errands()
        var events = await startWaiting(on: errands)
        errands.cancel()
        await errands.ended()
        #expect(await events.next() == .ended(cancelled: true))
    }

    @Test func lettingGoOfThemStopsTheErrandsUnderWay() async {
        var events: AsyncStream<Event>.Iterator
        do {
            let errands = Errands()
            events = await startWaiting(on: errands)
        }
        #expect(await events.next() == .ended(cancelled: true))
    }

    @Test func anErrandStartedAfterCancellingNeverRuns() async {
        let errands = Errands()
        let (ran, report) = AsyncStream.makeStream(of: Int.self)
        errands.cancel()
        errands.start { report.yield(1) }
        await errands.ended()
        report.finish()
        var runs: [Int] = []
        for await errand in ran { runs.append(errand) }
        #expect(runs.isEmpty)
    }
}
