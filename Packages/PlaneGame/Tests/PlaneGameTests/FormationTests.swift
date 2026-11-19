import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The formations later rounds bring, and the first round left as it was.
struct FormationTests {
    /// Every arrival over `seconds` in `round`, in groups as they arrived together.
    private func groups(
        over seconds: TimeInterval, round: Int, seed: UInt64 = 7, on field: PlaneGameField = phoneField
    ) -> [[PlaneGameSpawner.Arrival]] {
        var spawner = PlaneGameSpawner()
        var generator = SeededGenerator(seed: seed)
        let openings = PlaneGameSpawner.Openings(livesMissing: false, powerUpInPlay: true, round: round)
        // One frame at a time is short enough that no two patterns are due in the same one.
        return stride(from: 0, through: seconds, by: 1.0 / 120).map {
            spawner.arrivals(at: $0, in: field, openings: openings, using: &generator)
        }.filter { !$0.isEmpty }
    }

    private func isVee(_ group: [PlaneGameSpawner.Arrival]) -> Bool {
        group.count == 5 && group.allSatisfy { $0.kind == .spam }
    }

    private func isGate(_ group: [PlaneGameSpawner.Arrival]) -> Bool {
        group.count == 4 && group.allSatisfy { $0.kind == .stamp }
    }

    private func isPair(_ group: [PlaneGameSpawner.Arrival]) -> Bool {
        group.count == 2 && group.allSatisfy { $0.kind == .phish }
    }

    @Test(arguments: 1...5)
    func formationsWaitForTheirRounds(round: Int) {
        let all = groups(over: 300, round: round)
        #expect(all.contains(where: isVee) == (round >= PlaneGameRules.veesFromRound))
        #expect(all.contains(where: isGate) == (round >= PlaneGameRules.gatesFromRound))
        #expect(all.contains(where: isPair) == (round >= PlaneGameRules.phishPairsFromRound))
        #expect(all.joined().contains { $0.kind == .bulk } == (round >= PlaneGameRules.bulkFromRound))
    }

    @Test func theFirstRoundDrawsTheArrivalsItAlwaysDid() {
        // Captured from the spawner before rounds existed, for seed 7 on a phone, asked every twentieth of a second.
        let captured: [(PlaneGameThing.Kind, CGFloat)] = [
            (.spam, 55.036), (.spam, 224.879), (.spam, 124.829), (.spam, 148.423), (.star, 170.121),
            (.spam, 337.962), (.spam, 311.400), (.spam, 214.486), (.spam, 147.908), (.star, 288.519),
            (.stamp, 67.063), (.stamp, 174.235), (.stamp, 355.591), (.spam, 172.113), (.rapid, 363.013),
            (.spam, 164.955), (.postmark, 216.207), (.postmark, 80.360), (.spam, 113.142), (.stamp, 248.629),
        ]
        var spawner = PlaneGameSpawner()
        var generator = SeededGenerator(seed: 7)
        var arrivals: [PlaneGameSpawner.Arrival] = []
        var time: TimeInterval = 0
        while arrivals.count < captured.count {
            time += 0.05
            arrivals += spawner.arrivals(
                at: time, in: phoneField, openings: .init(livesMissing: false, powerUpInPlay: false),
                using: &generator)
        }
        for (arrival, (kind, x)) in zip(arrivals, captured) {
            #expect(arrival.kind == kind)
            #expect(abs(arrival.position.x - x) < 0.001)
        }
    }

    @Test func aVeeIsFiveSpamWithItsPointLeading() throws {
        let vee = try #require(groups(over: 300, round: 2).first(where: isVee))
        let spacing = PlaneGameRules.veeSpacing
        for (left, right) in zip(vee, vee.dropFirst()) {
            #expect(abs(right.position.x - left.position.x - spacing.width) < 0.001)
        }
        #expect(vee[2].position.y == vee.map(\.position.y).max())
        #expect(abs(vee[2].position.y - vee[1].position.y - spacing.height) < 0.001)
        #expect(abs(vee[1].position.y - vee[0].position.y - spacing.height) < 0.001)
    }

    @Test func aGateIsFourStampsWithRoomToFlyThrough() throws {
        let gate = try #require(groups(over: 300, round: 3).first(where: isGate))
        #expect(Set(gate.map(\.position.y)).count == 1)
        let inner = gate[2].position.x - gate[1].position.x - 2 * PlaneGameThing.Kind.stamp.radius
        #expect(inner >= 100)
    }

    @Test(arguments: [
        phoneField, PlaneGameField(size: CGSize(width: 240, height: 860), lanes: 12...228, ceiling: 80, row: 720),
    ])
    func everyFormationArrivesInsideTheLanes(field: PlaneGameField) {
        for arrival in groups(over: 300, round: 9, on: field).joined() {
            let reach = arrival.kind.radius + arrival.kind.swing
            #expect(field.lanes(inset: reach).contains(arrival.position.x))
        }
    }
}
