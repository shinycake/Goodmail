import Foundation

/// A paint as the document writes it, before gradient references are looked up.
enum SVGPaintSpec: Equatable {
    case none
    case color(VectorColor)
    case currentColor
    /// A gradient by ID, and what to paint when there is no such gradient (`nil` paints nothing).
    case reference(String, fallback: VectorColor?)
}

/// The styling an element ends up with: what it inherits, overridden by its presentation attributes, then the style
/// sheet, then its `style` attribute.
struct SVGStyle {
    var fill: SVGPaintSpec = .color(.black)
    var fillOpacity = 1.0
    var fillRule: VectorShape.FillRule = .nonZero
    var stroke: SVGPaintSpec = .none
    var strokeOpacity = 1.0
    var strokeWidth = 1.0
    var cap: VectorStroke.Cap = .butt
    var join: VectorStroke.Join = .miter
    var miterLimit = 4.0
    var color: VectorColor = .black
    var visible = true
    /// The product of this element's and its ancestors' `opacity`. Applied to each shape on its own, which differs
    /// from SVG's group compositing only where a translucent group's shapes overlap.
    var opacity = 1.0

    static func initial() -> SVGStyle { SVGStyle() }

    /// The style `element` draws with, inheriting from `self`, or `nil` when `display: none` hides it and its
    /// children.
    func child(for element: SVGElement, sheet: SVGStyleSheet) -> SVGStyle? {
        let declarations = Self.declarations(of: element, sheet: sheet)
        if declarations["display"] == "none" { return nil }
        var style = self
        for (property, value) in declarations where value != "inherit" {
            style.apply(property, value)
        }
        return style
    }

    /// Every styling property `element` sets, by precedence: presentation attributes, then the style sheet's
    /// rules, then the `style` attribute.
    static func declarations(of element: SVGElement, sheet: SVGStyleSheet) -> [String: String] {
        var declarations: [String: String] = [:]
        for (name, value) in element.attributes where properties.contains(name) {
            declarations[name] = value.trimmingCharacters(in: .whitespaces)
        }
        declarations.merge(sheet.declarations(for: element)) { $1 }
        declarations.merge(SVGStyleSheet.declarations(in: element.attributes["style"] ?? "")) { $1 }
        return declarations
    }

    private static let properties: Set<String> = [
        "fill", "fill-opacity", "fill-rule", "stroke", "stroke-opacity", "stroke-width", "stroke-linecap",
        "stroke-linejoin", "stroke-miterlimit", "color", "visibility", "display", "opacity", "stop-color",
        "stop-opacity",
    ]

    private mutating func apply(_ property: String, _ value: String) {
        switch property {
        case "fill": if let paint = SVGColor.paint(value) { fill = paint }
        case "fill-opacity": fillOpacity = Self.fraction(value) ?? fillOpacity
        case "fill-rule": fillRule = value == "evenodd" ? .evenOdd : .nonZero
        case "stroke": if let paint = SVGColor.paint(value) { stroke = paint }
        case "stroke-opacity": strokeOpacity = Self.fraction(value) ?? strokeOpacity
        case "stroke-width": strokeWidth = SVGLength.value(value).map { max(0, $0) } ?? strokeWidth
        case "stroke-linecap": cap = ["round": .round, "square": .square, "butt": .butt][value] ?? cap
        case "stroke-linejoin": join = ["round": .round, "bevel": .bevel, "miter": .miter][value] ?? join
        case "stroke-miterlimit": miterLimit = SVGLength.value(value).map { max(1, $0) } ?? miterLimit
        case "color": color = SVGColor.color(value) ?? color
        case "visibility": visible = value == "visible"
        case "opacity": opacity *= Self.fraction(value) ?? 1
        default: break  // display is handled by the caller; stop properties by gradients
        }
    }

    /// An opacity from 0 to 1, given as a number or a percentage.
    static func fraction(_ value: String) -> Double? {
        SVGLength.value(value).map { min(1, max(0, $0)) }
    }
}

/// A document's `<style>` rules, for the simple selectors exporters write: `tag`, `.class`, `tag.class` and
/// `#id`. Rules with combinators or pseudo-classes are ignored.
struct SVGStyleSheet {
    private struct Rule {
        let tag: String?
        let className: String?
        let id: String?
        let declarations: [String: String]
        let order: Int

        var specificity: Int { (id == nil ? 0 : 100) + (className == nil ? 0 : 10) + (tag == nil ? 0 : 1) }

        func matches(_ element: SVGElement) -> Bool {
            if let tag, tag != element.name { return false }
            if let id, id != element.id { return false }
            if let className {
                let classes = (element.attributes["class"] ?? "").split(whereSeparator: \.isWhitespace)
                if !classes.contains(Substring(className)) { return false }
            }
            return true
        }
    }

    private let rules: [Rule]

    init(_ css: String) {
        var rules: [Rule] = []
        let text = Self.removingComments(css)
        for block in text.split(separator: "}") {
            let parts = block.split(separator: "{", maxSplits: 1)
            guard parts.count == 2, !parts[0].contains("@") else { continue }
            let declarations = Self.declarations(in: String(parts[1]))
            for selector in parts[0].split(separator: ",") {
                guard
                    let rule = Self.rule(
                        selector.trimmingCharacters(in: .whitespacesAndNewlines),
                        declarations: declarations, order: rules.count)
                else { continue }
                rules.append(rule)
            }
        }
        self.rules = rules
    }

    func declarations(for element: SVGElement) -> [String: String] {
        let matching = rules.filter { $0.matches(element) }.sorted {
            ($0.specificity, $0.order) < ($1.specificity, $1.order)
        }
        return matching.reduce(into: [:]) { $0.merge($1.declarations) { $1 } }
    }

    /// `name: value; name: value` pairs, as in a rule's body or a `style` attribute.
    static func declarations(in text: String) -> [String: String] {
        var declarations: [String: String] = [:]
        for declaration in text.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let important = value.range(of: "!important") {
                value = value[..<important.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            declarations[name] = value
        }
        return declarations
    }

    private static func rule(_ selector: String, declarations: [String: String], order: Int) -> Rule? {
        guard !selector.isEmpty,
            selector.allSatisfy({ $0.isLetter || $0.isNumber || "-_.#".contains($0) })
        else { return nil }
        if selector.hasPrefix("#") {
            return Rule(
                tag: nil, className: nil, id: String(selector.dropFirst()), declarations: declarations,
                order: order)
        }
        let parts = selector.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 2, !selector.contains("#") else { return nil }
        let tag = parts[0].isEmpty ? nil : parts[0]
        let className = parts.count == 2 ? parts[1] : nil
        return Rule(tag: tag, className: className, id: nil, declarations: declarations, order: order)
    }

    private static func removingComments(_ css: String) -> String {
        var result = ""
        var rest = Substring(css)
        while let start = rest.range(of: "/*") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].range(of: "*/") else { return result }
            rest = rest[end.upperBound...]
        }
        return result + rest
    }
}
