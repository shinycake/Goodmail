public import Foundation

#if canImport(FoundationXML)
    public import FoundationXML  // XMLParser on Linux
#endif

/// Parses an SVG file into a `VectorImage`. Covers what logos use, the SVG Tiny 1.2 that BIMI requires and the
/// Illustrator-style CSS classes some exporters add: shapes, paths, groups, `use`, transforms, solid colors and
/// gradients. Text, images, clipping, masks and filters are left out, so a logo needing them draws without them.
public enum SVGDocument {
    /// The picture, or `nil` for data that isn't an SVG document or that would take more than `SVGPainter.budget`
    /// elements to draw.
    public static func image(from data: Data) -> VectorImage? {
        guard let root = SVGTreeBuilder.root(of: data), root.name == "svg" else { return nil }
        let index = SVGIndex(root: root)
        let viewBox = viewBox(of: root)
        var painter = SVGPainter(index: index, viewBox: viewBox)
        painter.paint(root, style: SVGStyle.initial(), transform: .identity, depth: 0)
        guard !painter.exhausted else { return nil }
        return VectorImage(viewBox: viewBox, shapes: painter.shapes)
    }

    /// The `viewBox`, or the width and height when there is none.
    private static func viewBox(of root: SVGElement) -> VectorRect {
        var scanner = NumberScanner(root.attributes["viewBox"] ?? "")
        let values = scanner.numbers()
        if values.count == 4, values[2] > 0, values[3] > 0 {
            return VectorRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        let width = SVGLength.value(root.attributes["width"]) ?? 0
        let height = SVGLength.value(root.attributes["height"]) ?? 0
        return VectorRect(x: 0, y: 0, width: width > 0 ? width : 100, height: height > 0 ? height : 100)
    }
}

/// An element of the parsed tree: its local name without namespace prefix, its attributes, and its children.
struct SVGElement {
    var name: String
    var attributes: [String: String]
    var children: [SVGElement] = []
    /// Character data, kept for `<style>` sheets.
    var text = ""

    var id: String? { attributes["id"] }

    /// The `href` or `xlink:href` target's ID, without its `#`.
    var reference: String? {
        guard let href = attributes["href"] ?? attributes["xlink:href"], href.hasPrefix("#") else { return nil }
        return String(href.dropFirst())
    }
}

/// What a document defines for reference: elements by ID, for `use` and gradients, and its style sheet.
struct SVGIndex {
    let elements: [String: SVGElement]
    let sheet: SVGStyleSheet

    init(root: SVGElement) {
        var elements: [String: SVGElement] = [:]
        var sheets: [String] = []
        func visit(_ element: SVGElement) {
            if let id = element.id, elements[id] == nil { elements[id] = element }
            if element.name == "style" { sheets.append(element.text) }
            element.children.forEach(visit)
        }
        visit(root)
        self.elements = elements
        sheet = SVGStyleSheet(sheets.joined(separator: "\n"))
    }
}

/// Builds the element tree with `XMLParser`. External entities stay unresolved, so a document can't reach the
/// network or the file system.
private final class SVGTreeBuilder: NSObject, XMLParserDelegate {
    private var stack: [SVGElement] = []
    private var root: SVGElement?

    static func root(of data: Data) -> SVGElement? {
        let parser = XMLParser(data: data)
        let builder = SVGTreeBuilder()
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        guard parser.parse(with: builder) else { return nil }
        return builder.root
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        stack.append(SVGElement(name: local, attributes: attributes))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += String(decoding: block, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
    ) {
        guard let element = stack.popLast() else { return }
        if stack.isEmpty { root = element } else { stack[stack.count - 1].children.append(element) }
    }
}

/// SVG lengths as plain numbers: user units and `px` alike, percentages as fractions of `reference`.
enum SVGLength {
    static func value(_ text: String?, reference: Double = 1) -> Double? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasSuffix("%") {
            text.removeLast()
            return Double(text).map { $0 / 100 * reference }
        }
        var scanner = NumberScanner(text)
        return scanner.number()
    }
}
