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

    private let personal = Account(id: AccountID(rawValue: "p"), email: "me@example.com", color: .blue, service: .gmail)
    private let work = Account(id: AccountID(rawValue: "w"), email: "work@example.com", color: .orange, service: .gmail)

    @Test func aViewOfOneAccountWearsItsColor() {
        #expect(Theme(accountID: work.id, among: [personal, work]) == .account(.orange))
        #expect(Theme(accountID: nil, among: [work]) == .account(.orange), "spanning one account is its view")
    }

    @Test func aViewSpanningAccountsWearsTheirBlend() {
        let theme = Theme(accountID: nil, among: [personal, work])
        #expect(theme == .blend(AccountBlend([.blue, .orange])))
        // The blend's tint is a dynamic color made afresh each time, so compare what it resolves to.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            #expect(
                theme.tint.resolvedColor(with: traits)
                    == AccountBlend([.blue, .orange]).tint.resolvedColor(with: traits))
        }
    }

    @Test func aGoneAccountsViewWearsTheSystemTint() {
        #expect(Theme(accountID: AccountID(rawValue: "gone"), among: [personal]).tint == .tintColor)
    }

    @Test func rowsMarkTheirAccountOnlyWhereTheViewSpansAccounts() {
        let own = Theme.account(.orange).rowAccount(work)
        #expect(own == .implied(.orange))
        #expect(own.badge(unread: true) == .dot(.systemOrange))
        #expect(own.badge(unread: false) == nil, "the view already says which account")
        #expect(own.spokenAccount == nil)

        let blended = Theme(accountID: nil, among: [personal, work]).rowAccount(work)
        #expect(blended == .shown(.orange, email: "work@example.com"))
        #expect(blended.badge(unread: true) == .dot(.systemOrange))
        #expect(blended.badge(unread: false) == .ring(.systemOrange))
        #expect(blended.spokenAccount == "work@example.com")
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
