import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

@MainActor
struct SwipeTintTests {
    private let picked = SwipeTint.custom(RGBColor(red: 0x12, green: 0x80, blue: 0x40))

    @Test func actionsThatDeleteOrReportAreRedAndTheRestClear() {
        let tints = SwipeTints.standard
        #expect(SwipeChoice.allCases.filter { tints[$0] == .red } == [.trash, .spam])
        #expect(SwipeChoice.allCases.filter { tints[$0] == .clear } == [.read, .star, .archive, .snooze])
    }

    @Test func aPickedTintStaysAndGoingBackToTheStandardOneRestoresTheDefaults() {
        var tints = SwipeTints.standard
        tints[.archive] = picked
        tints[.trash] = .clear
        #expect(tints[.archive] == picked)
        #expect(tints[.trash] == .clear)
        #expect(tints != .standard)
        tints[.archive] = .clear
        tints[.trash] = .red
        #expect(tints == .standard)
    }

    @Test func storedTintsReadBackAsThemselves() {
        var tints = SwipeTints.standard
        tints[.read] = picked
        tints[.spam] = .clear
        #expect(tints.stored == ["read": "#128040", "spam": "clear"])
        #expect(SwipeTints(stored: tints.stored) == tints)
    }

    @Test func storedTintsThisBuildDoesNotKnowAreSkipped() {
        let tints = SwipeTints(stored: ["read": "sparkly", "teleport": "red", "star": "#FF0000"])
        #expect(tints[.read] == .clear)
        #expect(tints[.star] == .custom(RGBColor(red: 255, green: 0, blue: 0)))
    }

    @Test func clearGlassIsNeverShaded() {
        #expect(SwipeTint.clear.picked == nil)
        #expect(SwipeTint.clear.shade == nil)
        #expect(SwipeTint.red.picked == .systemRed)
    }

    @Test func aPickedTintIsDeepUnderWhiteInDarkModeAndPaleUnderADeepSymbolInLightMode() throws {
        let shade = try #require(picked.shade)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let light = UITraitCollection(userInterfaceStyle: .light)
        // Compared by components: the shade's white is an RGB color, which never equals the grayscale `.white`.
        #expect(components(shade.symbol.resolvedColor(with: dark)) == components(.white))
        #expect(shade.fill.contrastRatio(with: shade.symbol, in: dark) >= ButtonShade.minimumContrast)
        #expect(shade.fill.contrastRatio(with: .white, in: light) < shade.fill.contrastRatio(with: .white, in: dark))
        #expect(shade.fill.contrastRatio(with: shade.symbol, in: light) >= ButtonShade.minimumContrast)
    }

    @Test func swipeButtonsWearTheirActionsTints() {
        var tints = SwipeTints.standard
        tints[.archive] = picked
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"), subject: "", snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: true, messageCount: 1,
            labelIDs: ["INBOX"])
        let buttons = SwipeArrangement.standard.buttons(for: thread, at: .inbox, on: .trailing, tints: tints)
        #expect(buttons.map(\.tint) == [picked, .clear, .red])
    }

    @Test func symbolsOnAFilledButtonAreWhiteOrBlackWhicheverReads() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let yellow = UIColor(RGBColor(red: 255, green: 230, blue: 0))
        let navy = UIColor(RGBColor(red: 0, green: 0, blue: 120))
        #expect(yellow.readableForeground.resolvedColor(with: traits) == .black)
        #expect(navy.readableForeground.resolvedColor(with: traits) == .white)
    }
}

/// A resolved color's red, green, blue and alpha, whatever color space it was made in.
private func components(_ color: UIColor) -> [CGFloat] {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return [red, green, blue, alpha]
}
