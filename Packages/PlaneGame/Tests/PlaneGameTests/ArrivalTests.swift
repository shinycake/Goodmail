import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What arrives when, and where.
struct ArrivalTests {
    /// Everything that arrives over `seconds`, asked for every frame, with the time it was asked for.
    private func arrivals(
        over seconds: TimeInterval, livesMissing: Bool, seed: UInt64 = 7, on field: PlaneGameField = phoneField
    ) -> [(time: TimeInterval, arrivals: [PlaneGameSpawner.Arrival])] {
        var spawner = PlaneGameSpawner()
        var generator = SeededGenerator(seed: seed)
        return stride(from: 0, through: seconds, by: 1.0 / 20).map { time in
            (time, spawner.arrivals(at: time, in: field, livesMissing: livesMissing, using: &generator))
        }
    }

    @Test func nothingArrivesBeforeTheFirstArrival() {
        var world = PlaneGameWorld(field: phoneField, launch: .fromBelow, after: 0.4, seed: 3)
        world.run(for: PlaneGameRules.firstArrival - frame)
        #expect(world.things.isEmpty)
        world.run(for: 2 * frame)
        #expect(!world.things.isEmpty)
    }

    @Test func lanesTwiceAsWideBringArrivalsTwiceAsOften() {
        let wide = PlaneGameField(size: CGSize(width: 776, height: 860), lanes: 12...764, ceiling: 80, row: 720)
        let onAPhone = arrivals(over: 120, livesMissing: false).count { !$0.arrivals.isEmpty }
        let onWide = arrivals(over: 120, livesMissing: false, on: wide).count { !$0.arrivals.isEmpty }
        #expect(abs(Double(onWide) / Double(onAPhone) - 2) < 0.1)
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
        let firstStamp = try #require(timeline.first { $0.arrivals.contains { $0.kind == .stamp } }?.time)
        let firstAny = try #require(timeline.first { !$0.arrivals.isEmpty }?.time)
        #expect(firstAny >= PlaneGameRules.firstArrival)
        #expect(firstStamp >= PlaneGameRules.stampsFrom)
        #expect(firstPostmark >= PlaneGameRules.postmarksFrom)
        #expect(firstPhish >= PlaneGameRules.phishFrom)
        #expect(firstRow >= PlaneGameRules.spamRowsFrom)
    }

    @Test(arguments: 1...20 as ClosedRange<UInt64>)
    func theOpeningSecondsBringOnlySingleSpamAndStars(seed: UInt64) {
        let opening = arrivals(over: PlaneGameRules.stampsFrom - 0.01, livesMissing: false, seed: seed)
        #expect(opening.allSatisfy { $0.arrivals.count <= 1 })
        #expect(opening.flatMap(\.arrivals).allSatisfy { [PlaneGameThing.Kind.spam, .star].contains($0.kind) })
    }

    @Test func aRowIsThreeSpamOnASlant() throws {
        let row = try #require(arrivals(over: 300, livesMissing: false).first { $0.arrivals.count == 3 }?.arrivals)
        #expect(row.map(\.kind) == [.spam, .spam, .spam])
        for (one, next) in zip(row, row.dropFirst()) {
            #expect(next.position.x - one.position.x == PlaneGameRules.rowSpacing.width)
            #expect(one.position.y - next.position.y == PlaneGameRules.rowSpacing.height)
        }
    }

    @Test func everythingArrivesAboveTheTopEdgeWithItsWeaveInsideTheLanes() {
        let all = arrivals(over: 300, livesMissing: true).flatMap(\.arrivals)
        #expect(all.count > 300)
        #expect(all.allSatisfy { $0.position.y <= -PlaneGameRules.arriveBeyond })
        #expect(
            all.allSatisfy {
                let reach = $0.kind.radius + $0.kind.swing
                return $0.position.x - reach >= phoneField.lanes.lowerBound
                    && $0.position.x + reach <= phoneField.lanes.upperBound
            })
    }

    @Test func arrivalsComeQuickerOverTheFirstTwoMinutes() {
        #expect(PlaneGameSpawner.interval(at: 0) == PlaneGameRules.firstInterval)
        #expect(abs(PlaneGameSpawner.interval(at: 60) - 0.975) < 0.0001)
        #expect(PlaneGameSpawner.interval(at: PlaneGameRules.hardeningTime) == PlaneGameRules.lastInterval)
        #expect(PlaneGameSpawner.interval(at: 600) == PlaneGameRules.lastInterval)
    }

    @Test(arguments: PlaneGameThing.Kind.allCases)
    func whatComesDownStaysInsideTheLanes(kind: PlaneGameThing.Kind) {
        var world = PlaneGameWorld.flying()
        world.add(kind, at: CGPoint(x: phoneField.lanes.lowerBound, y: -40))
        world.add(kind, at: CGPoint(x: phoneField.lanes.upperBound, y: -40))
        for _ in 0..<120 {
            world.advance(by: frame, input: PlaneGameInput())
            #expect(world.things.allSatisfy { phoneField.lanes.contains($0.position.x) })
        }
    }
}
