import UIKit

/// Draws quoted paragraphs in the editor as they read in mail: indented, with a bar on the side the line starts from.
nonisolated final class QuoteLayout: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
            paragraph.attributedString.attribute(.blockQuote, at: 0, effectiveRange: nil) != nil
        else { return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange) }
        let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
        var direction = RichText.Direction(attributes)
        if direction == .auto { direction = .detected(in: paragraph.attributedString.string) }
        return QuoteFragment(textElement, barOnRight: direction == .rightToLeft)
    }
}

nonisolated private final class QuoteFragment: NSTextLayoutFragment {
    private let barOnRight: Bool

    init(_ textElement: NSTextElement, barOnRight: Bool) {
        self.barOnRight = barOnRight
        super.init(textElement: textElement, range: textElement.elementRange)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not archived") }

    /// The bar sits outside the text's own bounds, in the indent.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(CGRect(origin: .zero, size: layoutFragmentFrame.size))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let width: CGFloat = 3
        let x = barOnRight ? point.x + layoutFragmentFrame.width - width : point.x
        context.saveGState()
        context.setFillColor(UIColor.tertiaryLabel.cgColor)
        context.fill(CGRect(x: x, y: point.y, width: width, height: layoutFragmentFrame.height))
        context.restoreGState()
        super.draw(at: point, in: context)
    }
}
