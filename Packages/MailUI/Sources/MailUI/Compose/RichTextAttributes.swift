import MailCore
import UIKit

nonisolated extension NSAttributedString.Key {
    /// A quoted paragraph's `RichText.QuoteLevel`, by raw value. Lists live in `NSParagraphStyle.textLists`, which
    /// the system's formatting panel also sets; UIKit has no quote of its own.
    static let blockQuote = NSAttributedString.Key("GoodmailBlockQuote")
    /// A run's `RichText.Size`, by raw value, so reading the text back doesn't guess it from point sizes. Absent
    /// means normal size.
    static let textSize = NSAttributedString.Key("GoodmailTextSize")
    /// A paragraph's direction when the writer set one, by raw value. Absent means it follows its first letter. The
    /// paragraph style always states the direction it reads in, since TextKit indents a paragraph left of
    /// `.natural` text even when that text reads from the right.
    static let paragraphDirection = NSAttributedString.Key("GoodmailParagraphDirection")
    /// A run's chosen `RichText.TextColor` as `#rrggbb`, so reading the text back doesn't guess it from the color it
    /// draws in. Absent means the reader's own color.
    static let textColor = NSAttributedString.Key("GoodmailTextColor")
}

/// The editor's side: formatted text as the attributes a `UITextView` shows and the system's formatting controls
/// change. Bold and italic are font traits, lists are `NSTextList`s, direction is the paragraph's base direction.
nonisolated extension RichText {
    init(_ text: NSAttributedString) {
        let string = text.string as NSString
        var paragraphs: [Paragraph] = []
        var location = 0
        while true {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            var content = range
            // Leave out the line break that ends the paragraph.
            while content.length > 0,
                CharacterSet.newlines.contains(UnicodeScalar(string.character(at: NSMaxRange(content) - 1)) ?? " ")
            {
                content.length -= 1
            }
            var paragraph = Paragraph()
            if range.length > 0 {
                let attributes = text.attributes(at: range.location)
                paragraph.block = Block(attributes)
                paragraph.quoteLevel = QuoteLevel(attributes)
                paragraph.direction = Direction(attributes)
            }
            text.forEachRun(in: content) { attributes, run in
                paragraph.append(
                    Run(
                        text: string.substring(with: run), styles: Set(attributes: attributes),
                        link: Self.link(in: attributes), size: Size(attributes), color: TextColor(attributes)))
            }
            paragraphs.append(paragraph)
            location = NSMaxRange(range)
            if location >= string.length {
                // A final line break starts one more, empty line.
                if content.length < range.length { paragraphs.append(Paragraph()) }
                break
            }
        }
        self.init(paragraphs)
    }

    func attributedString(font: UIFont) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let lineAttributes = paragraph.layoutAttributes(font: font).merging(Self.plainAttributes(font: font)) {
                $1
            }
            for run in paragraph.runs {
                var attributes = lineAttributes
                run.size.apply(to: &attributes, font: font)
                run.color.apply(to: &attributes)
                attributes.merge(run.styles.attributes(font: attributes[.font] as? UIFont ?? font)) { $1 }
                if let link = run.link { attributes[.link] = link }
                text.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            if index < paragraphs.count - 1 {
                text.append(NSAttributedString(string: "\n", attributes: lineAttributes))
            }
        }
        return text
    }

    /// What a caret at `location` types next: the size and color of the text it continues. That is the character
    /// before it, or, at the start of a line that has text, the line's first character, since the line break before
    /// it belongs to the line above. UIKit carries over a character's font and color but not the size and color this
    /// text reads back from, so without them typing would draw colored and go out plain.
    static func typingRun(
        in text: NSAttributedString, at location: Int, typingAttributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        let string = text.string as NSString
        func isLineBreak(_ index: Int) -> Bool {
            CharacterSet.newlines.contains(UnicodeScalar(string.character(at: index)) ?? " ")
        }
        let startsLine = location == 0 || isLineBreak(location - 1)
        let hasTextAfter = location < string.length && !isLineBreak(location)
        let source = startsLine && hasTextAfter ? location : location - 1
        guard (0..<string.length).contains(source) else { return typingAttributes }
        let continued = text.attributes(at: source)
        var typing = typingAttributes
        typing[.textSize] = continued[.textSize]
        TextColor(continued).apply(to: &typing)
        return typing
    }

    /// Unformatted text in `font`, in the label color: text with no color draws black, even in Dark Mode.
    static func plainAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        TextColor.automatic.apply(to: &attributes)
        return attributes
    }

    private static func link(in attributes: [NSAttributedString.Key: Any]) -> URL? {
        attributes[.link] as? URL ?? (attributes[.link] as? String).flatMap(URL.init(string:))
    }
}

nonisolated extension RichText.Paragraph {
    /// The attributes that lay a paragraph out, every one of them set or cleared.
    static let layoutKeys: [NSAttributedString.Key] = [.paragraphStyle, .blockQuote, .paragraphDirection]

    /// What every character of the paragraph carries for its layout and direction, indented to suit `font`. A key of
    /// `layoutKeys` that is missing is one the paragraph doesn't have.
    func layoutAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: style(font: font)]
        if quoteLevel.isQuoted { attributes[.blockQuote] = quoteLevel.rawValue }
        if direction != .auto { attributes[.paragraphDirection] = direction.rawValue }
        return attributes
    }

    private func style(font: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        // The way it reads, so the indent of a list or quote goes on the side the text starts from.
        let reads = direction == .auto ? RichText.Direction.firstLetter(in: text) : direction
        style.baseWritingDirection =
            switch reads {
            case nil, .auto: .natural
            case .leftToRight: .leftToRight
            case .rightToLeft: .rightToLeft
            }
        var indent = RichText.QuoteLevel.indent(font: font) * CGFloat(quoteLevel.rawValue)
        switch block {
        case .body: break
        case .bulleted, .numbered:
            style.textLists = [NSTextList(markerFormat: block == .bulleted ? .disc : .decimal, options: 0)]
            indent += font.pointSize * 1.5
        }
        style.headIndent = indent
        style.firstLineHeadIndent = indent
        return style
    }
}

nonisolated extension RichText.Block {
    init(_ attributes: [NSAttributedString.Key: Any]) {
        let list = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.last
        self = if let list { list.isOrdered ? .numbered : .bulleted } else { .body }
    }
}

nonisolated extension RichText.QuoteLevel {
    init(_ attributes: [NSAttributedString.Key: Any]) {
        self.init(rawValue: attributes[.blockQuote] as? Int ?? 0)
    }

    /// How far each level moves the text in from the side it starts from: the bar and a gap after it.
    static func indent(font: UIFont) -> CGFloat { (font.pointSize * 0.85).rounded() }

    /// The bar of the quote at `depth`, the same color that is sent.
    static func barUIColor(depth: Int) -> UIColor { UIColor(barColor(depth: depth)) }
}

nonisolated extension RichText.Direction {
    init(_ attributes: [NSAttributedString.Key: Any]) {
        self = (attributes[.paragraphDirection] as? String).flatMap(Self.init(rawValue:)) ?? .auto
    }
}

nonisolated extension Set<RichText.Style> {
    init(attributes: [NSAttributedString.Key: Any]) {
        let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        self.init()
        if traits.contains(.traitBold) { insert(.bold) }
        if traits.contains(.traitItalic) { insert(.italic) }
        if (attributes[.underlineStyle] as? Int ?? 0) != 0 { insert(.underline) }
        if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { insert(.strikethrough) }
    }

    /// The font and lines that show these styles on `font`.
    func attributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        var traits = font.fontDescriptor.symbolicTraits.subtracting([.traitBold, .traitItalic])
        if contains(.bold) { traits.insert(.traitBold) }
        if contains(.italic) { traits.insert(.traitItalic) }
        return [
            .font: font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) } ?? font,
            .underlineStyle: contains(.underline) ? NSUnderlineStyle.single.rawValue : 0,
            .strikethroughStyle: contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : 0,
        ]
    }
}

nonisolated extension RichText.Size {
    init(_ attributes: [NSAttributedString.Key: Any]) {
        self = (attributes[.textSize] as? String).flatMap(Self.init(rawValue:)) ?? .normal
    }

    /// Gives `attributes` this size of the message's `font`, keeping their bold and italic.
    func apply(to attributes: inout [NSAttributedString.Key: Any], font: UIFont) {
        let current = attributes[.font] as? UIFont ?? font
        attributes[.font] = UIFont(descriptor: current.fontDescriptor, size: font.pointSize * scale)
        attributes[.textSize] = self == .normal ? nil : rawValue
    }
}

nonisolated extension RichText.TextColor {
    init(_ attributes: [NSAttributedString.Key: Any]) {
        self = (attributes[.textColor] as? String).flatMap(RGBColor.init(hex:)).map(Self.init) ?? .automatic
    }

    /// How the editor shows it: the same value that is sent, or the label color that follows Dark Mode. Text with no
    /// color at all draws black, so the reader's own color is the label color here.
    var color: UIColor {
        switch self {
        case .automatic: .label
        case .ink(let ink): UIColor(ink.color)
        }
    }

    func apply(to attributes: inout [NSAttributedString.Key: Any]) {
        attributes[.foregroundColor] = color
        attributes[.textColor] = hex
    }
}

nonisolated extension NSMutableAttributedString {
    /// Draws each run in `range` in the color it is sent in. Pasted text brings colors of its own that the message
    /// doesn't carry, often black, which would vanish on a dark page here and still go out in the reader's color.
    func settleColors(in range: NSRange) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: length))
        forEachRun(in: range) { attributes, run in
            let color = RichText.TextColor(attributes).color
            if attributes[.foregroundColor] as? UIColor != color {
                addAttribute(.foregroundColor, value: color, range: run)
            }
        }
    }
}
