import Testing

@testable import MailCore

/// A slow read of a resource is dropped when a write overtook it, or for the labels, a newer read.
struct ReadTicketsTests {
    @Test func aReadWithNoWriteSinceIsCurrent() {
        let writes = OvertakingWrites()
        #expect(writes.isCurrent(writes.read()))
    }

    @Test func aWriteOvertakesEveryReadUnderWay() {
        var writes = OvertakingWrites()
        let first = writes.read()
        let second = writes.read()
        writes.wrote()
        #expect(!writes.isCurrent(first))
        #expect(!writes.isCurrent(second))
        #expect(writes.isCurrent(writes.read()))
    }

    @Test func aNewerReadOvertakesTheOlderOnes() {
        var reads = LatestRead()
        let older = reads.begin()
        let newer = reads.begin()
        #expect(!reads.isLatest(older))
        #expect(reads.isLatest(newer))
    }
}
