import CoreGraphics
import Testing

@testable import MailUI

@Suite("Undo toast placement")
struct UndoToastPlacementTests {
    /// Search and Compose as an iPhone 17 Pro lays them out: 38-point buttons centered 52 points above the bottom.
    private let ends = [CGRect(x: 33, y: 803, width: 38, height: 38), CGRect(x: 331, y: 803, width: 38, height: 38)]
    private let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)

    @Test("A toast that fits between the end buttons sits on their line")
    func fitsBetweenButtons() {
        let placement = UndoToastPlacement.choose(
            ends: ends, midX: 201, toastSize: CGSize(width: 208, height: 44), aboveInset: 98)
        #expect(placement == .inToolbar(centerY: 822))
        // The toast's bottom, 22 points below the line, sits this far above the bottom of the window.
        let bottom: CGFloat = 822 + 22 - 874
        #expect(placement.bottomConstant(in: bounds, toastHeight: 44) == bottom)
    }

    @Test("A toast that would come within the gap of a button goes above the toolbar")
    func tooWide() {
        let reach = 201 - 71 - UndoToastPlacement.buttonGap
        let fits = UndoToastPlacement.choose(
            ends: ends, midX: 201, toastSize: CGSize(width: 2 * reach, height: 44), aboveInset: 98)
        let wider = UndoToastPlacement.choose(
            ends: ends, midX: 201, toastSize: CGSize(width: 2 * reach + 1, height: 44), aboveInset: 98)
        #expect(fits == .inToolbar(centerY: 822))
        #expect(wider == .above(inset: 98))
        #expect(wider.bottomConstant(in: bounds, toastHeight: 44) == -98)
    }

    @Test("With one end button, the toast keeps its gap from that one")
    func oneButton() {
        let placement = UndoToastPlacement.choose(
            ends: [ends[1]], midX: 201, toastSize: CGSize(width: 208, height: 44), aboveInset: 98)
        #expect(placement == .inToolbar(centerY: 822))
    }

    @Test("Without open toolbar ends the toast goes above the bottom")
    func noEnds() {
        let placement = UndoToastPlacement.choose(
            ends: [], midX: 201, toastSize: CGSize(width: 208, height: 44), aboveInset: 46)
        #expect(placement == .above(inset: 46))
    }

    @Test("Buttons stacked in a bar down the side never carry the toast")
    func sideBar() {
        // iPhone Duo's outer display puts the toolbar in a column on the right: Search above Compose.
        let column = [CGRect(x: 418, y: 420, width: 38, height: 38), CGRect(x: 418, y: 600, width: 38, height: 38)]
        let placement = UndoToastPlacement.choose(
            ends: column, midX: 205, toastSize: CGSize(width: 208, height: 44), aboveInset: 34)
        #expect(placement == .above(inset: 34))
    }
}
