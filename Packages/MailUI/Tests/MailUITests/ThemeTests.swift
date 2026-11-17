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
        let font = Typography.system(.largeTitle, weight: .bold)
        #expect(theme.titleAttributes(font: font)[.foregroundColor] as? UIColor == .systemPurple)
        #expect(theme.titleBar(for: "Inbox", font: font) == nil)
    }

    @Test(arguments: [UIUserInterfaceLayoutDirection.leftToRight, .rightToLeft])
    func aGradientThemesTitleIsInTheTextColorOverAThinRoundedGradientBar(direction: UIUserInterfaceLayoutDirection)
        throws
    {
        let theme = Theme(accountID: nil, among: [personal, work], combined: .gradient)
        let font = Typography.system(.largeTitle, weight: .bold)
        let attributes = theme.titleAttributes(font: font)
        #expect(attributes[.foregroundColor] as? UIColor == .label)
        #expect(attributes[.underlineStyle] == nil, "the bar is drawn under the title, not as an underline")

        let bar = try #require(theme.titleBar(for: "Inbox", font: font))
        bar.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        let size = bar.intrinsicContentSize
        #expect(size.width == ceil(TitleInk("Inbox", font: font).width), "as wide as the title's line")
        #expect(size.height == GradientTitleBar.thickness(in: bar.traitCollection))
        #expect(size.height < font.pointSize / 8, "a thin line, not a thick bar")
        #expect(bar.sizeThatFits(CGSize(width: 20, height: 100)).width == 20, "never wider than the bar allows")

        bar.frame = CGRect(origin: .zero, size: size)
        // At 3x, so the corners' pixels lie wholly outside the rounded ends.
        let traits = UITraitCollection {
            $0.userInterfaceStyle = .light
            $0.displayScale = 3
        }
        let image = UIGraphicsImageRenderer(bounds: bar.bounds, format: UIGraphicsImageRendererFormat(for: traits))
            .image { _ in traits.performAsCurrent { bar.draw(bar.bounds) } }
        let left = try #require(image.color(at: CGPoint(x: 0.2, y: 0.5)))
        let right = try #require(image.color(at: CGPoint(x: 0.8, y: 0.5)))
        let (leading, trailing) = direction == .leftToRight ? (left, right) : (right, left)
        #expect(leading.isCloser(to: .systemBlue, than: .systemOrange, in: traits))
        #expect(trailing.isCloser(to: .systemOrange, than: .systemBlue, in: traits))
        // The bar's ends are rounded: at the first and last columns it draws, its top row is clear.
        let columns = try #require(image.cgImage?.width)
        let drawn = (0..<columns).filter {
            image.color(at: CGPoint(x: (CGFloat($0) + 0.5) / CGFloat(columns), y: 0.5)) != nil
        }
        let first = try #require(drawn.first)
        let last = try #require(drawn.last)
        #expect(image.color(at: CGPoint(x: (CGFloat(first) + 0.5) / CGFloat(columns), y: 0)) == nil)
        #expect(image.color(at: CGPoint(x: (CGFloat(last) + 0.5) / CGFloat(columns), y: 0)) == nil)
    }

    @Test(arguments: [UIUserInterfaceLayoutDirection.leftToRight, .rightToLeft], ["Inbox", "Mailboxes", "דואר נכנס"])
    func theTitleBarRunsFromTheFirstLettersInkToTheLasts(direction: UIUserInterfaceLayoutDirection, title: String)
        throws
    {
        let theme = Theme(accountID: nil, among: [personal, work], combined: .gradient)
        let font = Typography.system(.largeTitle, weight: .bold)
        let bar = try #require(theme.titleBar(for: title, font: font))
        bar.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        // One point wider than the line, as UIKit may give it, so the bar has to find the title's leading edge.
        let line = TitleInk(title, font: font)
        bar.frame = CGRect(x: 0, y: 0, width: ceil(line.width) + 1, height: bar.intrinsicContentSize.height)
        let traits = UITraitCollection { $0.displayScale = 3 }
        let image = UIGraphicsImageRenderer(bounds: bar.bounds, format: UIGraphicsImageRendererFormat(for: traits))
            .image { _ in traits.performAsCurrent { bar.draw(bar.bounds) } }
        let columns = try #require(image.cgImage?.width)
        let drawn = (0..<columns).filter {
            image.color(at: CGPoint(x: (CGFloat($0) + 0.5) / CGFloat(columns), y: 0.5)) != nil
        }
        let start = CGFloat(try #require(drawn.first)) / 3
        let end = CGFloat(try #require(drawn.last) + 1) / 3
        let origin = direction == .rightToLeft ? bar.bounds.width - line.width : 0
        #expect(line.ink.lowerBound > 0 || line.ink.upperBound < line.width, "the line has room beside its letters")
        #expect(abs(start - (origin + line.ink.lowerBound)) <= 0.5, "starts under the first letter's ink")
        #expect(abs(end - (origin + line.ink.upperBound)) <= 0.5, "ends under the last letter's ink")
    }

    @Test(arguments: [UIUserInterfaceLayoutDirection.leftToRight, .rightToLeft])
    func aGradientThemePaintsASymbolFromItsLeadingColorToItsTrailingOne(direction: UIUserInterfaceLayoutDirection)
        throws
    {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let square = try #require(
            UIImage(systemName: "square.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40)))
        let painted = Theme.gradient(AccountBlend([.blue, .orange])).paint(square, in: traits, direction: direction)
        #expect(painted.size == square.size)
        #expect(painted.renderingMode == .alwaysOriginal, "a tint would flatten the gradient to one color")
        let left = try #require(painted.color(at: CGPoint(x: 0.15, y: 0.5)))
        let right = try #require(painted.color(at: CGPoint(x: 0.85, y: 0.5)))
        let (leading, trailing) = direction == .leftToRight ? (left, right) : (right, left)
        #expect(leading.isCloser(to: .systemBlue, than: .systemOrange, in: traits))
        #expect(trailing.isCloser(to: .systemOrange, than: .systemBlue, in: traits))
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
        #expect(blended == .shown(.orange, name: "work@example.com"))
        #expect(blended.badge(unread: true) == .dot(.systemOrange))
        #expect(blended.badge(unread: false) == .ring(.systemOrange))
        #expect(blended.spokenAccount == "work@example.com")
    }

    @Test func voiceOverNamesARowsAccountByItsNickname() {
        var nicknamed = work
        nicknamed.nickname = "Work"
        let blended = Theme(accountID: nil, among: [personal, nicknamed], combined: .gradient).rowAccount(nicknamed)
        #expect(blended.spokenAccount == "Work")
    }

    @Test func contentTypographyIsTheSystemFont() {
        let system = UIFont.systemFont(ofSize: 17).familyName
        for font in [Typography.title, Typography.subject, Typography.body] {
            #expect(font.familyName == system, "\(font.fontName)")
        }
    }

    @Test func contentTypographyFollowsDynamicType() {
        // A font UIFontMetrics already scaled must not be scaled again, so ask Typography for each size.
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        let huge = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let body = Typography.system(.body, compatibleWith: large)
        #expect(body.pointSize == UIFont.preferredFont(forTextStyle: .body, compatibleWith: large).pointSize)
        #expect(Typography.system(.body, compatibleWith: huge).pointSize > body.pointSize)
    }
}

extension UIImage {
    /// The color at `point`, as a fraction of the image's width and height.
    fileprivate func color(at point: CGPoint) -> UIColor? {
        guard let cgImage else { return nil }
        let x = Int(point.x * CGFloat(cgImage.width))
        let y = Int(point.y * CGFloat(cgImage.height))
        guard let bitmap = RGBABitmap(width: 1, height: 1) else { return nil }
        bitmap.context.draw(
            cgImage, in: CGRect(x: -x, y: y - cgImage.height + 1, width: cgImage.width, height: cgImage.height))
        guard let pixel = bitmap.pixels, pixel[3] > 0 else { return nil }
        let alpha = CGFloat(pixel[3])
        return UIColor(
            red: CGFloat(pixel[0]) / alpha, green: CGFloat(pixel[1]) / alpha, blue: CGFloat(pixel[2]) / alpha, alpha: 1)
    }
}

extension UIColor {
    fileprivate func isCloser(to near: UIColor, than far: UIColor, in traits: UITraitCollection) -> Bool {
        func distance(to other: UIColor) -> CGFloat {
            let (mine, theirs) = (rgba, other.resolvedColor(with: traits).rgba)
            return pow(mine.red - theirs.red, 2) + pow(mine.green - theirs.green, 2) + pow(mine.blue - theirs.blue, 2)
        }
        return distance(to: near) < distance(to: far)
    }
}
