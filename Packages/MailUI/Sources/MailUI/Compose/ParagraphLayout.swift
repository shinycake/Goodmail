import UIKit

/// Keeps every paragraph in the editor laid out as one: its list, quote level and direction on each of its characters,
/// its paragraph style reading the way its text does. Typing works from the character before the caret, which can
/// drop the quote or keep a direction the first letter has since changed, so each edit is settled after it lands.
nonisolated extension RichText.Paragraph {
    /// The layout `attributes` give a paragraph whose text is `text`.
    init(layoutOf attributes: [NSAttributedString.Key: Any], text: String) {
        self.init(
            block: RichText.Block(attributes), quoteLevel: RichText.QuoteLevel(attributes),
            direction: RichText.Direction(attributes), runs: [RichText.Run(text: text)])
    }
}

nonisolated extension [NSAttributedString.Key: Any] {
    /// These attributes with `layout`'s in place of their own, keys it lacks taken away.
    func withLayout(_ layout: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = self
        for key in RichText.Paragraph.layoutKeys { attributes[key] = layout[key] }
        return attributes
    }
}

nonisolated extension NSAttributedString {
    /// Calls `body` with the range of each paragraph in the text, its line break included, and its text without it.
    func forEachParagraph(_ body: (NSRange, String) -> Void) {
        let string = string as NSString
        var location = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            body(paragraph, string.substring(with: paragraph).trimmingCharacters(in: .newlines))
            location = NSMaxRange(paragraph)
        }
    }

    /// Whether every character of `range` carries `layout`, and nothing more of it.
    fileprivate func has(_ layout: [NSAttributedString.Key: Any], in range: NSRange) -> Bool {
        var matches = true
        forEachRun(in: range) { attributes, _ in
            matches =
                matches
                && attributes[.paragraphStyle] as? NSParagraphStyle == layout[.paragraphStyle] as? NSParagraphStyle
                && attributes[.blockQuote] as? Int == layout[.blockQuote] as? Int
                && attributes[.paragraphDirection] as? String == layout[.paragraphDirection] as? String
        }
        return matches
    }
}

nonisolated extension NSMutableAttributedString {
    /// Gives every character of `range` the paragraph layout `layout`, taking away the layout keys it lacks.
    func setLayout(_ layout: [NSAttributedString.Key: Any], of range: NSRange) {
        for key in RichText.Paragraph.layoutKeys {
            if let value = layout[key] {
                addAttribute(key, value: value, range: range)
            } else {
                removeAttribute(key, range: range)
            }
        }
    }

    /// Lays out each paragraph `edited` touches as its first character says, reading in the direction its text now
    /// does. Leaves a paragraph that already is alone, so a keystroke rewrites no attributes.
    func settleLayout(around edited: NSRange, font: UIFont) {
        let string = string as NSString
        guard string.length > 0 else { return }
        let start = min(edited.location, string.length - 1)
        let touched = string.paragraphRange(
            for: NSRange(location: start, length: min(edited.length, string.length - start)))
        var location = touched.location
        while location < NSMaxRange(touched) {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            let text = string.substring(with: paragraph).trimmingCharacters(in: .newlines)
            let layout = RichText.Paragraph(layoutOf: attributes(at: paragraph.location), text: text)
                .layoutAttributes(font: font)
            if !has(layout, in: paragraph) { setLayout(layout, of: paragraph) }
            location = NSMaxRange(paragraph)
        }
    }
}

nonisolated extension FormattingCommand {
    /// What is typed at `range` next: the typing attributes with the layout of the paragraph it goes into. A line
    /// with no characters yet keeps the layout the typing attributes give it, unless typing lost the quote of the
    /// line it continues: then it has that line's paragraph style but not its quote, and gets the quote back.
    static func typingLayout(
        in text: NSAttributedString, at range: NSRange, typingAttributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        let string = text.string as NSString
        let paragraph = string.paragraphRange(for: NSRange(location: range.location, length: 0))
        if paragraph.length > 0, paragraph.location < range.location || NSMaxRange(range) < NSMaxRange(paragraph) {
            // Characters of the paragraph stay on one side of the edit: theirs is the layout.
            let kept = paragraph.location < range.location ? paragraph.location : NSMaxRange(range)
            return typingAttributes.withLayout(text.attributes(at: kept))
        }
        guard range.location > 0, typingAttributes[.blockQuote] == nil else { return typingAttributes }
        let before = text.attributes(at: range.location - 1)
        let sameStyle =
            before[.paragraphStyle] as? NSParagraphStyle == typingAttributes[.paragraphStyle] as? NSParagraphStyle
        return sameStyle ? typingAttributes.withLayout(before) : typingAttributes
    }
}
