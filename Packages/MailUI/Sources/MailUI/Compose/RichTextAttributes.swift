import UIKit

nonisolated extension NSAttributedString.Key {
    /// Marks a paragraph as quoted. Lists live in `NSParagraphStyle.textLists`, which the system's formatting panel
    /// also sets; UIKit has no quote of its own.
    static let blockQuote = NSAttributedString.Key("GoodmailBlockQuote")
    /// A run's `RichText.Size` and `RichText.TextColor`, by raw value, so reading the text back doesn't guess them
    /// from point sizes and color values. Absent means normal size and the reader's color.
    static let textSize = NSAttributedString.Key("GoodmailTextSize")
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
            let lineAttributes = paragraph.layoutAttributes(font: font).merging([.font: font]) { $1 }
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

    private static func link(in attributes: [NSAttributedString.Key: Any]) -> URL? {
        attributes[.link] as? URL ?? (attributes[.link] as? String).flatMap(URL.init(string:))
    }
}

nonisolated extension RichText.Paragraph {
    /// What every character of the paragraph carries for its layout and direction, indented to suit `font`.
    func layoutAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: style(font: font)]
        if block == .quote { attributes[.blockQuote] = true }
        return attributes
    }

    private func style(font: UIFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection =
            switch direction {
            case .auto: .natural
            case .leftToRight: .leftToRight
            case .rightToLeft: .rightToLeft
            }
        let indent = font.pointSize * 1.5
        switch block {
        case .body: break
        case .bulleted, .numbered:
            style.textLists = [NSTextList(markerFormat: block == .bulleted ? .disc : .decimal, options: 0)]
            style.headIndent = indent
            style.firstLineHeadIndent = indent
        case .quote:
            style.headIndent = indent
            style.firstLineHeadIndent = indent
        }
        return style
    }
}

nonisolated extension RichText.Block {
    init(_ attributes: [NSAttributedString.Key: Any]) {
        let list = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists.last
        self =
            if let list { list.isOrdered ? .numbered : .bulleted } else if attributes[.blockQuote] != nil {
                .quote
            } else {
                .body
            }
    }
}

nonisolated extension RichText.Direction {
    init(_ attributes: [NSAttributedString.Key: Any]) {
        self =
            switch (attributes[.paragraphStyle] as? NSParagraphStyle)?.baseWritingDirection {
            case .leftToRight: .leftToRight
            case .rightToLeft: .rightToLeft
            default: .auto
            }
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
        self = (attributes[.textColor] as? String).flatMap(Self.init(rawValue:)) ?? .automatic
    }

    /// How the editor shows it: the same value that is sent, or the label color that follows Dark Mode.
    var color: UIColor {
        guard let hex else { return .label }
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    func apply(to attributes: inout [NSAttributedString.Key: Any]) {
        attributes[.foregroundColor] = self == .automatic ? nil : color
        attributes[.textColor] = self == .automatic ? nil : rawValue
    }
}
