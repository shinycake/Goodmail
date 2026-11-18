import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What arrives when, and where.
struct ArrivalTests {
    /// Everything that arrives over `seconds`, asked for every frame, with the time it was asked for.
    private func arrivals(over seconds: TimeInterval, livesMissing: Bool, seed: UInt64 = 7)
        -> [(time: TimeInterval, arrivals: [PlaneGameSpawner.Arrival])]
    {
        var spawner = PlaneGameSpawner()
        var generator = SeededGenerator(seed: seed)
        return stride(from: 0, through: seconds, by: 1.0 / 20).map { time in
            (time, spawner.arrivals(at: time, in: phoneField, livesMissing: livesMissing, using: &generator))
        }
    }

    @Test func nothingArrivesBeforeTheFirstArrival() {
        var world = PlaneGameWorld(field: phoneField, launchingFrom: CGPoint(x: -40, y: 400), after: 0.4, seed: 3)
        world.run(for: PlaneGameRules.firstArrival - frame)
        #expect(world.things.isEmpty)
        world.run(for: 2 * frame)
        #expect(!world.things.isEmpty)
    }

    @Test func heartsArriveOnlyWhileALifeIsMissing() {
        let full = arrivals(over: 300, livesMissing: false).flatMap(\.arrivals)
        let missing = arrivals(over: 300, livesMissing: true).flatMap(\.arrivals)
        #expect(!full.contains { $0.kind == .heart })
        #expect(missing.contains { $0.kind == .heart })
    }

    @Test func eachKindArrivesOnlyAfterItsUnlockTime() throws {
        let timeline = arrivals(over: 300, livesMissing: false)
        let firstPostmark = try #require(timeline.first { $0.arrivals.contains { $0.kind == .postmark } }?.time)
        let firstPhish = try #require(timeline.first { $0.arrivals.contains { $0.kind == .phish } }?.time)
        let firstRow = try #require(timeline.first { $0.arrivals.count == 3 }?.time)
        let firstAny = try #require(timeline.first { !$0.arrivals.isEmpty }?.time)
        #expect(firstAny >= PlaneGameRules.firstArrival)
        #expect(firstPostmark >= PlaneGameRules.postmarksFrom)
        #expect(firstPhish >= PlaneGameRules.phishFrom)
        #expect(firstRow >= PlaneGameRules.spamRowsFrom)
    }

    @Test func aRowIsThreeSpamStaggeredOneBehindAnother() throws {
        let row = try #require(arrivals(over: 300, livesMissing: false).first { $0.arrivals.count == 3 }?.arrivals)
        #expect(row.map(\.kind) == [.spam, .spam, .spam])
        #expect(zip(row, row.dropFirst()).allSatisfy { $1.position.x > $0.position.x && $1.position.y > $0.position.y })
    }

    @Test func everythingArrivesInsideTheBandJustBeyondTheTrailingEdge() {
        let all = arrivals(over: 300, livesMissing: true).flatMap(\.arrivals)
        #expect(all.count > 300)
        #expect(all.allSatisfy { phoneField.band.contains($0.position.y) })
        #expect(all.allSatisfy { $0.position.x >= phoneField.size.width + PlaneGameRules.arriveBeyond })
    }

    @Test func arrivalsComeQuickerOverTheFirstTwoMinutes() {
        #expect(PlaneGameSpawner.interval(at: 0) == PlaneGameRules.firstInterval)
        #expect(abs(PlaneGameSpawner.interval(at: 60) - 0.85) < 0.0001)
        #expect(PlaneGameSpawner.interval(at: PlaneGameRules.hardeningTime) == PlaneGameRules.lastInterval)
        #expect(PlaneGameSpawner.interval(at: 600) == PlaneGameRules.lastInterval)
    }

    @Test(arguments: PlaneGameThing.Kind.allCases)
    func whatArrivesStaysInsideTheBandAsItComes(kind: PlaneGameThing.Kind) {
        var world = PlaneGameWorld.flying()
        world.add(kind, at: CGPoint(x: 440, y: phoneField.band.lowerBound))
        world.add(kind, at: CGPoint(x: 440, y: phoneField.band.upperBound))
        for _ in 0..<120 {
            world.advance(by: frame, input: PlaneGameInput())
            #expect(world.things.allSatisfy { phoneField.band.contains($0.position.y) })
        }
    }
}
