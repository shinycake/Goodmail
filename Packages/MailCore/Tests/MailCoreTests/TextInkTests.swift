import Foundation
import Testing

@testable import MailCore

struct TextInkTests {
    @Test(arguments: ButtonShadeTests.picks)
    func aPickedColorReadsOnALightPageAndADarkOne(pick: RGBColor) {
        let ink = TextInk(pick).color
        #expect(ink.contrastRatio(with: TextInk.lightPage) >= TextInk.minimumContrast)
        #expect(ink.contrastRatio(with: TextInk.darkPage) >= TextInk.minimumContrast)
    }

    @Test func aColorThatAlreadyReadsOnBothIsKept() {
        let red = RGBColor(red: 0xE0, green: 0x35, blue: 0x2B)
        #expect(TextInk(red).color == red)
    }

    @Test(arguments: ButtonShadeTests.picks)
    func choosingTheSameColorAgainChangesNothing(pick: RGBColor) {
        let once = TextInk(pick).color
        #expect(TextInk(once).color == once)
    }

    @Test func aTooPaleColorDeepensInItsOwnHue() {
        let yellow = RGBColor(red: 0xFF, green: 0xCC, blue: 0x00)
        let ink = TextInk(yellow).color
        #expect(ink.lightness < yellow.lightness)
        #expect(ink.red > ink.blue && ink.green > ink.blue, "still a yellow, not a gray")
    }

    @Test func onlyAColorThatAlreadyReadsIsTakenExactly() {
        let red = RGBColor(red: 0xE0, green: 0x35, blue: 0x2B)
        #expect(TextInk(exactly: red)?.color == red)
        #expect(TextInk(exactly: RGBColor(red: 0, green: 0, blue: 0)) == nil, "black vanishes on a dark page")
    }
}
