import Testing
import UIKit

@testable import MailUI

@MainActor
struct SwipeLayoutTests {
    private let layout = SwipeLayout(count: 2, rowWidth: 402, rowHeight: 110)

    @Test func buttonsWaitPastTheEdgeBeforeTheSwipe() {
        let placements = layout.placements(for: .tracking(0))
        #expect(placements.allSatisfy { $0.offset == -SwipeLayout.diameter && !$0.isVisible })
    }

    @Test func buttonsSlideInFromTheEdgeAtFullSize() {
        let halfway = layout.placements(for: .tracking(layout.revealWidth / 2))
        #expect(halfway.allSatisfy { $0.isVisible })
        // Partway through, each is between the edge and its resting place, the inner one further along.
        #expect(halfway[0].offset < layout.restingOffset(0))
        #expect(halfway[1].offset < layout.restingOffset(1))
        #expect(halfway[1].offset > halfway[0].offset)
    }

    @Test func buttonsRestInPlaceOnceRevealedAndDoNotOvershoot() {
        for distance in [layout.revealWidth, layout.revealWidth + 30] {
            let placements = layout.placements(for: .tracking(distance))
            #expect(placements.map(\.offset) == [layout.restingOffset(0), layout.restingOffset(1)])
        }
    }

    @Test func aFullSwipeGrowsTheEdgeMostButtonToTheFinger() {
        let distance: CGFloat = 300
        #expect(layout.reveal(at: distance) == .fullSwipe(distance))
        let placements = layout.placements(for: .fullSwipe(distance))
        #expect(!placements[1].isVisible)
        #expect(
            placements[0]
                == SwipePlacement(
                    offset: SwipeLayout.inset, width: distance - SwipeLayout.inset - SwipeLayout.spacing,
                    height: 110 - 2 * SwipeLayout.verticalInset, isVisible: true))
    }

    @Test func aFullSwipeCoversTheRowWithoutLeavingIt() {
        let placements = layout.placements(for: .fullSwipe(1000))
        #expect(placements[0].offset == SwipeLayout.inset)
        #expect(placements[0].width == 402 - 2 * SwipeLayout.inset)
    }

    @Test func aFullSwipeNeverShrinksTheButtonInAShortRow() {
        let short = SwipeLayout(count: 1, rowWidth: 402, rowHeight: 50)
        let placement = short.placements(for: .fullSwipe(250))[0]
        #expect(placement.height == SwipeLayout.diameter)
    }

    @Test func aShortSwipeOnlyTracks() {
        #expect(!layout.reveal(at: layout.revealWidth).isFullSwipe)
    }
}
