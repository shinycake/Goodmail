import CoreGraphics
import Testing

@testable import MailUI

@Suite("Minimized messages placement")
struct DraftDockPlacementTests {
    /// Search and Compose as an iPhone 17 Pro lays them out: 38-point buttons centered 52 points above the bottom.
    private let ends = [CGRect(x: 33, y: 803, width: 38, height: 38), CGRect(x: 331, y: 803, width: 38, height: 38)]
    private let lane = CGRect(x: 0, y: 0, width: 402, height: 874)

    private func line(ends: [CGRect]) -> BottomLine {
        BottomLine(lane: lane, ends: ends, bottom: 874, barsInset: 98)
    }

    @Test("Between Search and Compose, the messages sit on their line with the gap to each")
    func betweenButtons() {
        let placement = DraftDockPlacement.choose(line: line(ends: ends), height: 48)
        let room = 201 - 71 - DraftDockPlacement.buttonGap
        #expect(placement == .inToolbar(CGRect(x: 201 - room, y: 822 - 24, width: 2 * room, height: 48)))
    }

    @Test("With only Compose reporting a frame, they keep the same room from both ends")
    func oneButton() {
        #expect(
            DraftDockPlacement.choose(line: line(ends: [ends[1]]), height: 48)
                == DraftDockPlacement.choose(line: line(ends: ends), height: 48))
    }

    @Test("Between buttons far apart, they grow only so wide")
    func widthCap() {
        let wide = BottomLine(
            lane: CGRect(x: 0, y: 0, width: 1200, height: 800),
            ends: [CGRect(x: 20, y: 740, width: 38, height: 38), CGRect(x: 1142, y: 740, width: 38, height: 38)],
            bottom: 800, barsInset: 80)
        #expect(DraftDockPlacement.choose(line: wide, height: 48).frame.width == DraftDockPlacement.widestInToolbar)
    }

    @Test("Without a toolbar middle, they float above the toolbar")
    func floats() {
        let placement = DraftDockPlacement.choose(line: line(ends: []), height: 48)
        let width = DraftDockPlacement.widestFloating
        let y = 874 - 98 - DraftDockPlacement.floatingGap - 48
        #expect(placement == .floating(CGRect(x: 201 - width / 2, y: y, width: width, height: 48)))
    }

    @Test("Too little room between the buttons floats them")
    func tooNarrow() {
        let close = [CGRect(x: 120, y: 803, width: 38, height: 38), CGRect(x: 244, y: 803, width: 38, height: 38)]
        guard case .floating = DraftDockPlacement.choose(line: line(ends: close), height: 48) else {
            Issue.record("Expected the messages to float")
            return
        }
    }

    @Test("Buttons in a bar down the side have no middle, so the messages float")
    func sideBar() {
        let side = [CGRect(x: 360, y: 300, width: 38, height: 38), CGRect(x: 360, y: 600, width: 38, height: 38)]
        guard case .floating = DraftDockPlacement.choose(line: line(ends: side), height: 48) else {
            Issue.record("Expected the messages to float")
            return
        }
    }

    @Test("On a fold lane, they center on the lane, not the window")
    func foldLane() {
        let half = BottomLine(lane: CGRect(x: 420, y: 0, width: 380, height: 800), ends: [], bottom: 800, barsInset: 40)
        #expect(DraftDockPlacement.choose(line: half, height: 48).frame.midX == 610)
    }
}
