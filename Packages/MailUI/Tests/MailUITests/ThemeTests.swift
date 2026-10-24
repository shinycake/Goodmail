import MailCore
import Testing
import UIKit

@testable import MailUI

@MainActor
struct ThemeTests {
    @Test func blendDropsDuplicateColorsKeepingAccountOrder() {
        #expect(AccountBlend([.teal, .blue, .teal]).colors == [.teal, .blue])
    }

    @Test func blendSpacesStopsEvenlyFromStartToEnd() {
        let stops = AccountBlend([.blue, .purple, .orange]).gradientStops
        #expect(stops.map(\.color) == [.blue, .purple, .orange])
        #expect(stops.map(\.location) == [0, 0.5, 1])
    }

    @Test func singleAccountBlendIsFlat() {
        let stops = AccountBlend([.green]).gradientStops
        #expect(stops.map(\.color) == [.green, .green])
        #expect(AccountBlend([.green]).tint == UIColor.systemGreen)
    }

    @Test func blendTintAveragesTheAccountColors() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let tint = AccountBlend([.blue, .orange]).tint.resolvedColor(with: traits)
        let blue = UIColor.systemBlue.resolvedColor(with: traits)
        let orange = UIColor.systemOrange.resolvedColor(with: traits)
        #expect(abs(tint.red - (blue.red + orange.red) / 2) < 0.001)
        #expect(abs(tint.blue - (blue.blue + orange.blue) / 2) < 0.001)
    }

    @Test func contentTypographyIsNewYork() {
        for font in [Typography.title, Typography.subject, Typography.body] {
            #expect(font.fontName.contains("NewYork"), "\(font.fontName)")
        }
    }
}

extension UIColor {
    fileprivate var red: CGFloat { components.red }
    fileprivate var blue: CGFloat { components.blue }

    private var components: (red: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, blue)
    }
}
