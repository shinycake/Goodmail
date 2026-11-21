import CoreGraphics
import Testing

@testable import MailUI

/// Which quick actions a hovered row's capsule has room for.
struct HoverFitTests {
    @Test func everyActionShowsWhenTheyAllFit() {
        let fit = HoverFit(actions: 5, room: 400)
        #expect(fit.shown == 5)
        #expect(!fit.overflows)
        #expect(fit.size.width <= 400)
    }

    @Test func actionsThatDontFitGoUnderMore() {
        // Room for three buttons: two actions, then More.
        let room = 2 * HoverFit.padding + 3 * HoverFit.buttonSide + 2 * HoverFit.spacing
        let fit = HoverFit(actions: 5, room: room)
        #expect(fit.shown == 2)
        #expect(fit.overflows)
        #expect(fit.buttons == 3)
        #expect(fit.size.width == room, "the capsule is exactly as wide as its buttons")
    }

    @Test func theCapsuleNeverOutgrowsItsRoomWhileThereIsRoomForOneButton() {
        for room in stride(from: CGFloat(34), through: 300, by: 1) {
            #expect(HoverFit(actions: 6, room: room).size.width <= room, "at \(room) points")
        }
    }

    @Test func anUnboundedRoomShowsEverything() {
        #expect(HoverFit(actions: 6, room: .greatestFiniteMagnitude).shown == 6)
    }
}
