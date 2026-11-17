import Foundation

/// The inline elements of HTML whose blocks are already lines: each tag is dropped, and the ones that give words a
/// look, bold, italics, a heading or a link, give it to the words inside them.
enum InlineMarkup {
    /// An element that gives the words inside it a look, while it is open.
    private enum Element: Equatable {
        case bold(name: String)
        case italic(name: String)
        case link(URL?)

        var name: String {
            switch self {
            case .bold(let name), .italic(let name): name
            case .link: "a"
            }
        }

        init?(name: String, attributes: Substring) {
            switch name {
            case "b", "strong", "h1", "h2", "h3", "h4", "h5", "h6": self = .bold(name: name)
            case "i", "em", "cite": self = .italic(name: name)
            case "a": self = .link(Self.href(in: attributes).flatMap(StyledText.link))
            default: return nil
            }
        }

        private static func href(in attributes: Substring) -> String? {
            guard let match = attributes.firstMatch(of: /(?i)\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/)
            else { return nil }
            return (match.output.1 ?? match.output.2 ?? match.output.3).map { HTMLEntities.decode(String($0)) }
        }
    }

    /// The words between the tags, entities decoded, each with the look of the elements open around it. Words outside
    /// any link that spell a web address link to it.
    static func read(_ html: String) -> StyledText {
        var text = StyledText()
        var open: [Element] = []
        var rest = html[...]
        func words(_ raw: Substring) {
            let decoded = HTMLEntities.decode(String(raw))
            let style = open.reduce(into: StyledText.Style()) { style, element in
                switch element {
                case .bold: style.insert(.bold)
                case .italic: style.insert(.italic)
                case .link: break
                }
            }
            let link = open.last { if case .link = $0 { true } else { false } }
            if case .link(let url) = link {
                text.append(decoded, style: style, link: url)
            } else {
                for run in StyledText.linking(decoded).runs { text.append(run.text, style: style, link: run.link) }
            }
        }
        while let tag = rest.firstMatch(of: /<(\/?)([a-zA-Z][a-zA-Z0-9]*)?([^>]*)>/) {
            words(rest[..<tag.range.lowerBound])
            rest = rest[tag.range.upperBound...]
            guard let name = tag.output.2.map({ $0.lowercased() }) else { continue }
            if tag.output.1.isEmpty {
                if let element = Element(name: name, attributes: tag.output.3), !tag.output.3.hasSuffix("/") {
                    open.append(element)
                }
            } else if let index = open.lastIndex(where: { $0.name == name }) {
                open.remove(at: index)
            }
        }
        words(rest)
        return text
    }
}
