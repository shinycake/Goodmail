import UIKit

/// The formatting at the writer's selection: what the controls show as on, and what a tap on them turns off.
struct Formatting: Equatable {
    /// The styles every selected character has, or the next typed one gets.
    var styles: Set<RichText.Style>
    /// The link the selection is, or the caret is inside.
    var link: URL?
    /// The layout and direction of the paragraph the selection starts in.
    var block: RichText.Block
    var direction: RichText.Direction

    init(text: NSAttributedString, selection: NSRange, typingAttributes: [NSAttributedString.Key: Any]) {
        if selection.length == 0 {
            styles = Set(attributes: typingAttributes)
        } else {
            var common = Set(RichText.Style.allCases)
            text.enumerateAttributes(in: selection) { attributes, _, _ in
                common.formIntersection(Set(attributes: attributes))
            }
            styles = common
        }
        link = FormattingCommand.linkRange(in: text, selection: selection).flatMap { range in
            var whole = NSRange()
            let link = text.attribute(.link, at: range.location, longestEffectiveRange: &whole, in: range)
            return NSEqualRanges(whole, range) ? (link as? URL ?? (link as? String).flatMap(URL.init(string:))) : nil
        }
        let start = (text.string as NSString).paragraphRange(for: NSRange(location: selection.location, length: 0))
        let paragraph =
            start.length > 0 ? text.attributes(at: start.location, effectiveRange: nil) : typingAttributes
        block = RichText.Block(paragraph)
        direction = RichText.Direction(paragraph)
    }
}

/// What a formatting control asks for. `edit` works it out as one replacement of the text, so the composer applies
/// it, and undoes it, in one step.
enum FormattingCommand: Equatable {
    /// Turns a style on for the selection, or off when all of it already has it.
    case toggle(RichText.Style)
    /// Lays out the selected paragraphs as `block`, or back as plain paragraphs when they already are.
    case block(RichText.Block)
    case direction(RichText.Direction)
    /// Links the selection, or the link the caret is in; a caret elsewhere gets the address typed out as the link.
    /// `nil` removes the link.
    case link(URL?)

    struct Edit {
        /// The characters replaced, and what replaces them. Both are empty when only typing changes.
        var range: NSRange
        var replacement: NSAttributedString
        var selection: NSRange
        var typingAttributes: [NSAttributedString.Key: Any]
    }

    func edit(
        text: NSAttributedString, selection: NSRange, typingAttributes: [NSAttributedString.Key: Any], font: UIFont
    ) -> Edit {
        let current = Formatting(text: text, selection: selection, typingAttributes: typingAttributes)
        switch self {
        case .toggle(let style):
            let turnOn = !current.styles.contains(style)
            func toggled(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
                var styles = Set(attributes: attributes)
                if turnOn { styles.insert(style) } else { styles.remove(style) }
                return styles.attributes(font: attributes[.font] as? UIFont ?? font)
            }
            guard selection.length > 0 else {
                return Edit(
                    range: selection, replacement: NSAttributedString(), selection: selection,
                    typingAttributes: typingAttributes.merging(toggled(typingAttributes)) { $1 })
            }
            let replacement = NSMutableAttributedString(attributedString: text.attributedSubstring(from: selection))
            replacement.enumerateAttributes(in: NSRange(location: 0, length: replacement.length)) {
                attributes, run, _ in
                replacement.addAttributes(toggled(attributes), range: run)
            }
            return Edit(
                range: selection, replacement: replacement, selection: selection, typingAttributes: typingAttributes)
        case .block(let block):
            let target = current.block == block ? .body : block
            return Self.relayout(text, selection: selection, typingAttributes: typingAttributes, font: font) {
                $0.block = target
            }
        case .direction(let direction):
            return Self.relayout(text, selection: selection, typingAttributes: typingAttributes, font: font) {
                $0.direction = direction
            }
        case .link(let url):
            if let range = Self.linkRange(in: text, selection: selection) {
                let replacement = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
                let whole = NSRange(location: 0, length: replacement.length)
                if let url { replacement.addAttribute(.link, value: url, range: whole) }
                if url == nil { replacement.removeAttribute(.link, range: whole) }
                return Edit(
                    range: range, replacement: replacement, selection: selection, typingAttributes: typingAttributes)
            }
            guard let url else {
                return Edit(
                    range: selection, replacement: NSAttributedString(), selection: selection,
                    typingAttributes: typingAttributes)
            }
            var attributes = typingAttributes
            attributes[.link] = url
            let replacement = NSAttributedString(string: url.absoluteString, attributes: attributes)
            return Edit(
                range: selection, replacement: replacement,
                selection: NSRange(location: selection.location + replacement.length, length: 0),
                typingAttributes: typingAttributes)
        }
    }

    /// Gives every paragraph the selection touches the layout `change` makes, keeping each one's own block and
    /// direction otherwise. The caret's line continues with it too, even when it has no characters yet.
    private static func relayout(
        _ text: NSAttributedString, selection: NSRange, typingAttributes: [NSAttributedString.Key: Any],
        font: UIFont, change: (inout RichText.Paragraph) -> Void
    ) -> Edit {
        func relaidOut(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var paragraph = RichText.Paragraph(
                block: RichText.Block(attributes), direction: RichText.Direction(attributes))
            change(&paragraph)
            var attributes = attributes
            attributes[.blockQuote] = nil
            return attributes.merging(paragraph.layoutAttributes(font: font)) { $1 }
        }
        let string = text.string as NSString
        let range = string.paragraphRange(for: selection)
        let replacement = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
        var location = 0
        while location < replacement.length {
            let paragraph = (replacement.string as NSString).paragraphRange(
                for: NSRange(location: location, length: 0))
            let attributes = relaidOut(replacement.attributes(at: paragraph.location, effectiveRange: nil))
            replacement.removeAttribute(.blockQuote, range: paragraph)
            for key in [NSAttributedString.Key.paragraphStyle, .blockQuote] {
                if let value = attributes[key] { replacement.addAttribute(key, value: value, range: paragraph) }
            }
            location = NSMaxRange(paragraph)
        }
        return Edit(
            range: range, replacement: replacement, selection: selection,
            typingAttributes: relaidOut(typingAttributes))
    }

    /// What Return does instead of starting a line: on an empty list item or quoted line it ends the list or quote,
    /// as in Notes and Mail. `nil` lets the line break go in.
    static func onReturn(
        in text: NSAttributedString, selection: NSRange, typingAttributes: [NSAttributedString.Key: Any]
    ) -> FormattingCommand? {
        guard selection.length == 0 else { return nil }
        let line = (text.string as NSString).lineRange(for: selection)
        let isEmpty = (text.string as NSString).substring(with: line).trimmingCharacters(in: .newlines).isEmpty
        let block = Formatting(text: text, selection: selection, typingAttributes: typingAttributes).block
        return isEmpty && block != .body ? .block(block) : nil
    }

    /// The characters a link change applies to: the selection, or the whole link around a caret inside one.
    static func linkRange(in text: NSAttributedString, selection: NSRange) -> NSRange? {
        guard selection.length == 0 else { return selection }
        guard selection.location > 0, selection.location < text.length else { return nil }
        var range = NSRange()
        let link = text.attribute(
            .link, at: selection.location, longestEffectiveRange: &range,
            in: NSRange(location: 0, length: text.length))
        return link != nil && range.location < selection.location ? range : nil
    }

    /// The address a writer typed for a link: `https://` is assumed for a bare domain and `mailto:` for an email
    /// address. `nil` when it can't be one, or when it names a scheme other than web and mail, such as
    /// `javascript:`, which a recipient's client could run.
    static func linkURL(from typed: String) -> URL? {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !typed.contains(" ") else { return nil }
        if typed.firstMatch(of: /^[a-zA-Z][a-zA-Z0-9+.-]*:/) != nil {
            guard let url = URL(string: typed), let scheme = url.scheme?.lowercased(),
                ["http", "https", "mailto"].contains(scheme)
            else { return nil }
            return url
        }
        if ComposeViewModel.isAddress(typed) { return URL(string: "mailto:" + typed) }
        guard typed.contains(".") else { return nil }
        return URL(string: "https://" + typed)
    }
}
