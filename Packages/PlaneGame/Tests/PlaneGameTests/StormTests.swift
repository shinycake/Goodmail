import Foundation
import Testing

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The Reply-All Storm dashes from post to post firing fans of replies aimed at the plane.
struct StormTests {
    @Test func itDashesToANewPostAfterEachVolleyAndHoldsThere() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(3)
        var rests: Set<Int> = []
        var last = try #require(world.boss).position.x
        let lanes = phoneField.lanes(inset: try #require(world.boss).radius)
        for _ in 0..<Int(12 / frame) {
            world.advance(by: frame, input: PlaneGameInput())
            let x = try #require(world.boss).position.x
            #expect(abs(x - last) <= PlaneGameRules.stormDash * CGFloat(frame) + 0.001)
            #expect(lanes.contains(x))
            #expect(abs(x - phoneField.startingPlace.x) <= PlaneGameRules.stormReach + 0.001)
            if x == last { rests.insert(Int(x.rounded())) }
            last = x
        }
        #expect(rests.count >= 4)
    }

    @Test func itsMiddleReplyLandsWhereThePlaneWas() throws {
        var world = PlaneGameWorld.flying()
        world.advance(by: frame, input: PlaneGameInput(slide: 120))
        world.meetBoss(3)
        while !world.things.contains(where: { $0.kind == .reply }) {
            world.advance(by: frame, input: PlaneGameInput())
        }
        let target = world.plane.position.x
        let replies = world.things.filter { $0.kind == .reply }.sorted { $0.drift < $1.drift }
        let middle = replies[replies.count / 2]
        world.advance(by: frame, input: PlaneGameInput(slide: -200))
        var reply = try #require(world.things.first { $0.id == middle.id })
        while reply.position.y < phoneField.row {
            world.advance(by: frame, input: PlaneGameInput())
            guard let next = world.things.first(where: { $0.id == middle.id }) else { break }
            reply = next
        }
        #expect(abs(reply.position.x - target) < 10)
    }

    @Test func aPlaneThatStaysIsHitAndOneThatStepsAsideIsNot() {
        var staying = PlaneGameWorld.flying()
        staying.meetBoss(3)
        staying.run(for: PlaneGameRules.stormReplyEvery + 2)
        #expect(staying.lives == PlaneGameRules.lives - 1)

        var stepping = PlaneGameWorld.flying()
        stepping.meetBoss(3)
        while !stepping.things.contains(where: { $0.kind == .reply }) {
            stepping.advance(by: frame, input: PlaneGameInput())
        }
        stepping.advance(by: frame, input: PlaneGameInput(slide: PlaneGameRules.stormFan / 2))
        stepping.run(for: 1.5)
        #expect(stepping.lives == PlaneGameRules.lives)
    }

    @Test func angryItRepliesTwiceInQuickSuccession() throws {
        var world = PlaneGameWorld.flying()
        world.meetBoss(3)
        world.changeBoss { $0.hitsLeft = $0.hits / 2 }
        var volleys: [(time: TimeInterval, count: Int)] = []
        for _ in 0..<Int(6 / frame) {
            let sent = world.newThings(over: frame).filter { $0.kind == .reply }
            if !sent.isEmpty { volleys.append((world.elapsed, sent.count)) }
        }
        #expect(volleys.count >= 4)
        #expect(volleys.allSatisfy { $0.count == 5 })
        let gaps = zip(volleys, volleys.dropFirst()).map { $1.time - $0.time }
        let long = max(
            PlaneGameRules.stormReplyEvery - PlaneGameRules.stormQuicker, PlaneGameRules.stormQuickestReply)
        #expect(abs(gaps[0] - PlaneGameRules.stormEchoGap) < 2 * frame)
        #expect(abs(gaps[1] - long) < 2 * frame)
        #expect(abs(gaps[2] - PlaneGameRules.stormEchoGap) < 2 * frame)
    }

    @Test func repliesCantBeShotAndLeaveThroughTheSides() {
        var world = PlaneGameWorld.flying()
        world.addAhead(.reply, by: 200)
        world.run(for: 0.2, input: PlaneGameInput(isFiring: true))
        #expect(!world.bursts.contains { $0.kind == .tick })
        world.things.removeAll()
        world.add(.reply, at: CGPoint(x: phoneField.lanes.upperBound - 5, y: 100), drift: 300)
        world.run(for: 0.5)
        #expect(world.things.isEmpty)
        world.addAhead(.reply, by: 0)
        world.advance(by: frame, input: PlaneGameInput())
        #expect(world.lives == PlaneGameRules.lives - 1)
    }
}
