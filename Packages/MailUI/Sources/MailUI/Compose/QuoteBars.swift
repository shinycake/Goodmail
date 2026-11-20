import UIKit

/// The message body's editor: a text view that draws each quote's bar beside its paragraphs, as Mail does. UIKit has
/// no quote of its own, so the bars are drawn behind the text from where TextKit laid the quoted paragraphs out.
final class BodyTextView: UITextView {
    /// Lazy: `init(usingTextLayoutManager:)` reaches UIKit without running this class's property initializers.
    private lazy var quoteBars = QuoteBars()

    override func layoutSubviews() {
        super.layoutSubviews()
        if quoteBars.superview !== self { insertSubview(quoteBars, at: 0) }
        quoteBars.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(contentSize.height, bounds.height))
        quoteBars.show(QuoteBarLayout(self))
    }
}

/// One quote's bar: the paragraphs it runs beside, at its depth, on the side the quote starts from.
nonisolated struct QuoteBar: Equatable {
    var depth: Int
    var isOnRight: Bool
    var top: CGFloat
    var bottom: CGFloat
}

/// Where the bars go in a text view: each bar, how far apart the depths are, and the text's edges.
nonisolated struct QuoteBarLayout: Equatable {
    var bars: [QuoteBar] = []
    /// The indent one level moves text by, which places each deeper bar.
    var step: CGFloat = 0
    var edges: UIEdgeInsets = .zero

    /// A laid-out paragraph, as far as its bars go.
    struct Paragraph {
        var level: Int
        var isRightToLeft: Bool
        var top: CGFloat
        var bottom: CGFloat
    }

    init() {}

    /// The bars for the text `textView` shows, from the frames TextKit gave its paragraphs.
    @MainActor init(_ textView: UITextView) {
        let inset = textView.textContainerInset
        let padding = textView.textContainer.lineFragmentPadding
        edges = UIEdgeInsets(top: inset.top, left: inset.left + padding, bottom: 0, right: inset.right + padding)
        step = RichText.QuoteLevel.indent(font: textView.font ?? .preferredFont(forTextStyle: .body))
        var paragraphs: [Paragraph] = []
        if let layout = textView.textLayoutManager {
            layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) {
                fragment in
                guard let paragraph = fragment.textElement as? NSTextParagraph,
                    paragraph.attributedString.length > 0
                else { return true }
                let text = paragraph.attributedString
                let attributes = text.attributes(at: 0)
                var direction = RichText.Direction(attributes)
                if direction == .auto { direction = .detected(in: text.string) }
                let frame = fragment.layoutFragmentFrame
                paragraphs.append(
                    Paragraph(
                        level: RichText.QuoteLevel(attributes).rawValue, isRightToLeft: direction == .rightToLeft,
                        top: frame.minY, bottom: frame.maxY))
                return true
            }
        }
        bars = Self.bars(for: paragraphs)
    }

    /// Joins the bars of neighbouring paragraphs: a quote's bar runs on past a deeper quote inside it and stops at a
    /// paragraph quoted less deeply. It stays on the side its first paragraph starts from, as the HTML's does.
    static func bars(for paragraphs: [Paragraph]) -> [QuoteBar] {
        var finished: [QuoteBar] = []
        /// The bars still running, outermost first.
        var running: [QuoteBar] = []
        for paragraph in paragraphs {
            let keep = running.prefix { $0.depth <= paragraph.level }.count
            finished += running[keep...]
            running.removeSubrange(keep...)
            for index in running.indices { running[index].bottom = paragraph.bottom }
            for depth in stride(from: running.count + 1, through: paragraph.level, by: 1) {
                running.append(
                    QuoteBar(
                        depth: depth, isOnRight: paragraph.isRightToLeft, top: paragraph.top,
                        bottom: paragraph.bottom))
            }
        }
        return finished + running
    }
}

/// Draws quote bars: rounded, in the color each depth is sent in, the outermost nearest the edge.
final class QuoteBars: UIView {
    private var layout = QuoteBarLayout()

    static let width: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func show(_ layout: QuoteBarLayout) {
        guard layout != self.layout else { return }
        self.layout = layout
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let edges = layout.edges
        for bar in layout.bars {
            let offset = CGFloat(bar.depth - 1) * layout.step
            let x = bar.isOnRight ? bounds.width - edges.right - offset - Self.width : edges.left + offset
            // A little shy of the lines' full height, so a bar reads as marking the text rather than the gaps.
            let frame = CGRect(
                x: x, y: edges.top + bar.top + 2, width: Self.width, height: max(bar.bottom - bar.top - 4, 0))
            RichText.QuoteLevel.barUIColor(depth: bar.depth).setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: Self.width / 2).fill()
        }
    }
}
