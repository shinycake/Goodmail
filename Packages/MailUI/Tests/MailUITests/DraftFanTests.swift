import CoreGraphics
import Testing

@testable import MailUI

@Suite("Drafts fanning out of the pill")
struct DraftFanTests {
    private static let pill = CGRect(x: 16, y: 796, width: 76, height: 44)

    /// Where `card` ends up under `transform`, applied about its centre as a view's is.
    private func tucked(_ card: CGRect, by transform: CGAffineTransform) -> CGRect {
        let centred = CGAffineTransform(translationX: -card.midX, y: -card.midY)
            .concatenating(transform)
            .concatenating(CGAffineTransform(translationX: card.midX, y: card.midY))
        return card.applying(centred)
    }

    @Test(
        "A tucked card is as wide as the pill and centred on it",
        arguments: [
            CGRect(x: 16, y: 454, width: 370, height: 300),  // above
            CGRect(x: -400, y: 700, width: 370, height: 300),  // left of
            CGRect(x: 500, y: 790, width: 200, height: 160),  // right of
        ])
    func tucksIntoThePill(card: CGRect) {
        let rect = tucked(card, by: DraftFan.tucked(card, into: Self.pill))
        #expect(abs(rect.width - Self.pill.width) < 0.001)
        #expect(abs(rect.midX - Self.pill.midX) < 0.001)
        #expect(abs(rect.midY - Self.pill.midY) < 0.001)
    }

    @Test("A card already the pill's width is only moved")
    func onlyMoves() {
        let card = CGRect(x: 200, y: 100, width: 76, height: 120)
        let transform = DraftFan.tucked(card, into: Self.pill)
        #expect(transform.a == 1)
        #expect(transform.d == 1)
        #expect(transform.tx == Self.pill.midX - card.midX)
        #expect(transform.ty == Self.pill.midY - card.midY)
    }

    @Test("The front card starts at once, each one behind 0.05 later")
    func deals() {
        #expect(DraftFan.delay(behind: 0, of: 3) == 0)
        #expect(abs(DraftFan.delay(behind: 1, of: 3) - 0.05) < 1e-9)
        #expect(abs(DraftFan.delay(behind: 2, of: 3) - 0.1) < 1e-9)
    }

    @Test("A single card starts at once")
    func single() {
        #expect(DraftFan.delay(behind: 0, of: 1) == 0)
    }

    @Test("However many there are, the last starts by 0.25", arguments: [2, 6, 7, 20, 100])
    func capped(count: Int) {
        let delays = (0..<count).map { DraftFan.delay(behind: $0, of: count) }
        #expect(delays.allSatisfy { $0 <= 0.25 + 1e-9 })
        #expect(delays == delays.sorted())
    }
}
