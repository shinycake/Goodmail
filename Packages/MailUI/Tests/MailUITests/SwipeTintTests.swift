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

    @Test func clearGlassHasNoFillOfItsOwn() {
        #expect(SwipeTint.clear.fill == nil)
        #expect(SwipeTint.red.fill == .systemRed)
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
