import Testing
import UIKit

@testable import MailUI

@MainActor
struct SwipeLayoutTests {
    private let layout = SwipeLayout(count: 2, rowWidth: 402, rowHeight: 110)

    @Test func buttonsWaitPastTheEdgeBeforeTheSwipe() {
        let placements = layout.placements(for: .tracking(0))
        #expect(placements.allSatisfy { $0.offset == -layout.diameter && !$0.isVisible })
    }

    @Test func buttonsSlideInFromTheEdgeAtFullSize() {
        let halfway = layout.placements(for: .tracking(layout.revealDistance / 2))
        #expect(halfway.allSatisfy { $0.isVisible })
        // Partway through, each is between the edge and its resting place, the inner one further along.
        #expect(halfway[0].offset < layout.restingOffset(0))
        #expect(halfway[1].offset < layout.restingOffset(1))
        #expect(halfway[1].offset > halfway[0].offset)
    }

    @Test func buttonsRestInPlaceOnceRevealedAndDoNotOvershoot() {
        for distance in [layout.revealDistance, layout.revealDistance + 30] {
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
        #expect(placement.height == SwipeLayout.minimumDiameter)
    }

    @Test func aShortSwipeOnlyTracks() {
        #expect(!layout.reveal(at: layout.revealDistance).isFullSwipe)
        #expect(!layout.reveal(at: layout.fullSwipeDistance).isFullSwipe)
        #expect(layout.reveal(at: layout.fullSwipeDistance + 1).isFullSwipe)
    }

    /// On a 402-point row, a full swipe fires a little short of halfway across, however many buttons the side holds.
    @Test(arguments: 1...3)
    func aFullSwipeFiresUnderHalfwayAcrossTheRow(count: Int) {
        let side = SwipeLayout(count: count, rowWidth: 402, rowHeight: 110)
        #expect(side.fullSwipeDistance >= 402 * SwipeLayout.minimumFullSwipeFraction)
        #expect(side.fullSwipeDistance < 402 * 0.47)
        // The buttons are all out before it, with room to stop.
        #expect(side.fullSwipeDistance - side.revealDistance >= SwipeLayout.fullSwipeMargin)
    }

    @Test func aFastFlickThatShowedEveryButtonFires() {
        let distance = layout.revealDistance
        #expect(!layout.firesOnRelease(at: distance, travelled: distance, speed: 0))
        #expect(layout.firesOnRelease(at: distance, travelled: distance, speed: SwipeLayout.flickSpeed))
    }

    @Test func aQuickFlickThatOnlyStartsTheRevealDoesNotFire() {
        let distance = layout.revealDistance - 1
        #expect(!layout.firesOnRelease(at: distance, travelled: distance, speed: 3000))
    }

    @Test func aBriskSwipeShortOfFlickSpeedDoesNotFire() {
        let distance = layout.fullSwipeDistance - 1
        #expect(!layout.firesOnRelease(at: distance, travelled: distance, speed: SwipeLayout.flickSpeed - 1))
    }

    @Test func aFullSwipeOnThreeButtonsCoversTheStackItTakesOver() {
        let three = SwipeLayout(count: 3, rowWidth: 402, rowHeight: 110)
        let distance = three.fullSwipeDistance + 1
        let capsule = three.placements(for: three.reveal(at: distance))[0]
        let stack = three.placements(for: .tracking(three.revealDistance))
        #expect(capsule.offset + capsule.width >= stack[2].offset + stack[2].width)
    }

    @Test func buttonsGrowWithTheTextSizeUpToTheirLargest() {
        var roomy = SwipeLayout(count: 2, rowWidth: 402, rowHeight: 300)
        roomy.preferredDiameter = 84
        #expect(roomy.diameter == 84)
        roomy.preferredDiameter = 200
        #expect(roomy.diameter == SwipeLayout.maximumDiameter)
    }

    @Test func buttonsShrinkToLeaveRoomToSwipePastThem() {
        let narrow = SwipeLayout(count: 3, rowWidth: 320, rowHeight: 110)
        #expect(narrow.diameter < SwipeLayout.baseDiameter)
        #expect(narrow.revealWidth <= 320 * SwipeLayout.maximumRevealFraction)
    }

    @Test func buttonsFitInsideTheRowsHeight() {
        let short = SwipeLayout(count: 1, rowWidth: 402, rowHeight: 76)
        #expect(short.diameter == 76 - 2 * SwipeLayout.rowClearance)
    }

    @Test func revealedButtonsShareTheRowBetweenThemForTouches() {
        let placements = layout.placements(for: .tracking(layout.revealDistance))
        let areas = placements.map { placement in
            let outset = layout.touchOutset(for: placement)
            return (
                inner: placement.offset + placement.width + outset.width, outer: placement.offset - outset.width,
                height: placement.height + 2 * outset.height
            )
        }
        // Each takes the row's full height, and the two meet halfway between their glass.
        #expect(areas.allSatisfy { $0.height == 110 })
        #expect(areas[0].inner == areas[1].outer)
    }
}
