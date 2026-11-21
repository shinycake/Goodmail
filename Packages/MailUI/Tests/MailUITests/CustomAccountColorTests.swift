import MailCore
import Testing
import UIKit

@testable import MailUI

/// Names MailCore's `RGBColor` in full, since on Mac Catalyst QuickDraw's is in scope too.
@MainActor
struct CustomAccountColorTests {
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    @Test func aLegiblePickIsShownAsPicked() {
        let blue = MailCore.RGBColor(red: 0, green: 90, blue: 200)
        let shown = AccountColor.custom(blue).uiColor
        #expect(shown.resolvedColor(with: light) == UIColor(blue).resolvedColor(with: light))
    }

    @Test(arguments: [
        MailCore.RGBColor(red: 10, green: 10, blue: 40), MailCore.RGBColor(red: 250, green: 250, blue: 200),
        MailCore.RGBColor(red: 0, green: 0, blue: 0), MailCore.RGBColor(red: 255, green: 255, blue: 255),
    ])
    func anyPickStandsOutFromTheBackgroundInLightAndDarkMode(color: MailCore.RGBColor) {
        let shown = AccountColor.custom(color).uiColor
        for traits in [light, dark] {
            #expect(shown.contrastRatio(with: .systemBackground, in: traits) >= AccountBlend.legibleContrast)
        }
    }

    @Test func increaseContrastAsksMoreOfAPick() {
        let traits = UITraitCollection {
            $0.userInterfaceStyle = .light
            $0.accessibilityContrast = .high
        }
        let shown = AccountColor.custom(MailCore.RGBColor(red: 120, green: 170, blue: 255)).uiColor
        #expect(shown.contrastRatio(with: .systemBackground, in: traits) >= 4.5)
    }

    @Test func aPickedColorJoinsTheGradient() {
        let picked = AccountColor.custom(MailCore.RGBColor(red: 200, green: 40, blue: 120))
        #expect(AccountBlend([.blue, picked]).gradientStops.map(\.color) == [.blue, picked])
    }
}
