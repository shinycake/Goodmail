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

    @Test func blendTintIsTheFirstAccountColorLegibleOnTheBackground() {
        let tint = AccountBlend([.yellow, .blue]).tint
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        #expect(
            tint.resolvedColor(with: light) == UIColor.systemBlue.resolvedColor(with: light), "yellow on white is faint"
        )
        #expect(tint.resolvedColor(with: dark) == UIColor.systemYellow.resolvedColor(with: dark))
    }

    @Test func blendTintFallsBackToTheMostLegibleColorWhenNoneReachesTheMinimum() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let colors: [AccountColor] = [.yellow, .mint]
        let best = colors.map(\.uiColor).max {
            $0.contrastRatio(with: .systemBackground, in: light) < $1.contrastRatio(with: .systemBackground, in: light)
        }
        #expect(AccountBlend(colors).tint.resolvedColor(with: light) == best?.resolvedColor(with: light))
    }

    @Test func contrastRatioRunsFromOneToTwentyOne() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        #expect(abs(UIColor.black.contrastRatio(with: .white, in: traits) - 21) < 0.01)
        #expect(UIColor.white.contrastRatio(with: .white, in: traits) == 1)
    }

    private let personal = Account(id: AccountID(rawValue: "p"), email: "me@example.com", color: .blue, service: .gmail)
    private let work = Account(id: AccountID(rawValue: "w"), email: "work@example.com", color: .orange, service: .gmail)

    @Test(arguments: [CombinedTheme.gradient, .solid(.mint)])
    func aViewOfOneAccountWearsItsColor(combined: CombinedTheme) {
        #expect(Theme(accountID: work.id, among: [personal, work], combined: combined) == .account(.orange))
        #expect(
            Theme(accountID: nil, among: [work], combined: combined) == .account(.orange),
            "spanning one account is its view")
    }

    @Test func aViewSpanningAccountsWearsTheirGradientWithALegibleTint() {
        let theme = Theme(accountID: nil, among: [personal, work], combined: .gradient)
        #expect(theme == .gradient(AccountBlend([.blue, .orange])))
        // The tint is a dynamic color made afresh each time, so compare what it resolves to.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            #expect(
                theme.tint.resolvedColor(with: traits)
                    == AccountBlend([.blue, .orange]).tint.resolvedColor(with: traits))
        }
    }

    @Test func aViewSpanningAccountsWearsTheChosenSolidColorInstead() {
        let theme = Theme(accountID: nil, among: [personal, work], combined: .solid(.purple))
        #expect(theme == .solid(.purple))
        #expect(theme.tint == .systemPurple)
        let font = Typography.serif(.largeTitle, weight: .bold)
        #expect(theme.titleColor(for: "Inbox", font: font, direction: .leftToRight) == .systemPurple)
    }

    @Test(arguments: [UIUserInterfaceLayoutDirection.leftToRight, .rightToLeft])
    func aGradientThemesTitleIsPaintedInThePattern(direction: UIUserInterfaceLayoutDirection) {
        let theme = Theme(accountID: nil, among: [personal, work], combined: .gradient)
        let font = Typography.serif(.largeTitle, weight: .bold)
        let title = theme.titleColor(for: "Inbox", font: font, direction: direction)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(title.cgColor.pattern != nil)
    }

    @Test func aGoneAccountsViewWearsTheSystemTint() {
        #expect(
            Theme(accountID: AccountID(rawValue: "gone"), among: [personal], combined: .gradient).tint == .tintColor)
    }

    @Test func rowsMarkTheirAccountOnlyWhereTheViewSpansAccounts() {
        let own = Theme.account(.orange).rowAccount(work)
        #expect(own == .implied(.orange))
        #expect(own.badge(unread: true) == .dot(.systemOrange))
        #expect(own.badge(unread: false) == nil, "the view already says which account")
        #expect(own.spokenAccount == nil)

        let blended = Theme(accountID: nil, among: [personal, work], combined: .solid(.green)).rowAccount(work)
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
