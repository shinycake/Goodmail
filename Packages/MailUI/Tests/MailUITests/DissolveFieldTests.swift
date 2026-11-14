import CoreGraphics
import Testing

@testable import MailUI

struct DissolveFieldTests {
    private let row = CGSize(width: 402, height: 88)

    private func field(
        budget: Int = 5000, from edge: DissolveField.Edge = .right, seed: UInt64 = 7,
        hasContent: (CGRect) -> Bool = { _ in true }
    ) -> DissolveField {
        DissolveField(size: row, budget: budget, from: edge, seed: seed, hasContent: hasContent)
    }

    @Test func tilesCoverOnlyTheDrawnPartsOfTheRow() {
        // Text in the left half only.
        let text = CGRect(x: 0, y: 0, width: 201, height: 88)
        let dust = field(hasContent: { $0.intersects(text) })
        #expect(!dust.particles.isEmpty)
        #expect(dust.particles.allSatisfy { $0.frame.intersects(text) })
        #expect(dust.particles.allSatisfy { CGRect(origin: .zero, size: row).contains($0.frame) })
    }

    @Test func anEmptyRowMakesNoDust() {
        #expect(field(hasContent: { _ in false }).particles.isEmpty)
    }

    @Test(arguments: [100, 800, 1800])
    func tilesGrowUntilTheyFitTheBudget(budget: Int) {
        let dust = field(budget: budget)
        #expect(dust.particles.count <= budget)
        #expect(dust.tile > DissolveField.minimumTile)
    }

    @Test func aRowWithinTheBudgetUsesTheFinestDust() {
        #expect(field(budget: .max).tile == DissolveField.minimumTile)
    }

    @Test(arguments: [DissolveField.Edge.left, .right])
    func theFrontSweepsFromItsEdgeAndTheDustBlowsTheWayItTravels(edge: DissolveField.Edge) throws {
        let dust = field(from: edge)
        let byX = dust.particles.sorted { $0.frame.midX < $1.frame.midX }
        let first = try #require(edge == .left ? byX.first : byX.last).frame.midX
        let last = try #require(edge == .left ? byX.last : byX.first).frame.midX
        let nearEdge = dust.particles.filter { $0.frame.midX == first }
        let farEdge = dust.particles.filter { $0.frame.midX == last }
        // The far column lets go only after every tile at the near edge has.
        #expect(nearEdge.map(\.delay).max()! < farEdge.map(\.delay).min()!)
        let away: CGFloat = edge == .left ? 1 : -1
        #expect(dust.particles.allSatisfy { $0.drift.dx * away > 0 })
    }

    @Test func everyTileIsGoneByTheEnd() {
        #expect(field().particles.allSatisfy { $0.delay + $0.lifetime <= DissolveField.duration })
    }

    @Test func theSameSeedScattersTheSameWay() {
        #expect(field(seed: 42) == field(seed: 42))
        #expect(field(seed: 42) != field(seed: 43))
    }
}
