import CoreText
import UIKit

/// The thin capsule of an account blend's gradient that sits under a large title, from the first letter's ink to
/// the last's, so a view spanning accounts shows their colors without coloring the letters. It goes in the
/// navigation item's `largeSubtitleView`, so it collapses with the large title.
final class GradientTitleBar: UIView {
    /// How thick the bar is at the default text size. It scales with the large title.
    static let thickness: CGFloat = 3

    private let blend: AccountBlend
    private let title: TitleInk

    /// A bar in `blend` under `title`.
    init(blend: AccountBlend, title: TitleInk) {
        self.blend = blend
        self.title = title
        super.init(frame: .zero)
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The bar's thickness at the text size in `traits`.
    static func thickness(in traits: UITraitCollection) -> CGFloat {
        UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: thickness, compatibleWith: traits)
    }

    /// As wide as the title's line, so the view lines up with the title on both sides and the bar can sit under
    /// the ink inside it.
    override var intrinsicContentSize: CGSize {
        CGSize(width: ceil(title.width), height: Self.thickness(in: traitCollection))
    }

    /// No wider than `size` offers, so a title the bar truncates keeps the bar inside the bar's margins.
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let ideal = intrinsicContentSize
        return CGSize(width: min(ideal.width, size.width), height: ideal.height)
    }

    override func draw(_ rect: CGRect) {
        let thickness = Self.thickness(in: traitCollection)
        // The title's line starts at the leading edge: the left one, or the right one right to left.
        let origin = effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.maxX - title.width : bounds.minX
        let bar = CGRect(
            x: origin + title.ink.lowerBound, y: bounds.midY - thickness / 2,
            width: title.ink.upperBound - title.ink.lowerBound, height: thickness
        ).intersection(bounds)
        guard
            !bar.isEmpty, let context = UIGraphicsGetCurrentContext(),
            let gradient = blend.gradient(in: traitCollection, direction: effectiveUserInterfaceLayoutDirection)
        else { return }
        UIBezierPath(roundedRect: bar, cornerRadius: thickness / 2).addClip()
        context.drawLinearGradient(
            gradient, start: CGPoint(x: bar.minX, y: 0), end: CGPoint(x: bar.maxX, y: 0), options: [])
    }
}

/// Where a title's letters are drawn on its line: the line's typographic width, which includes the space beside
/// the first and last letters, and the span of their ink from the line's left end.
struct TitleInk: Equatable {
    let width: CGFloat
    let ink: ClosedRange<CGFloat>

    /// `title` set on one line in `font`.
    init(_ title: String, font: UIFont) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: [.font: font]))
        width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ink = glyphs.isEmpty ? 0...0 : glyphs.minX...glyphs.maxX
    }
}
