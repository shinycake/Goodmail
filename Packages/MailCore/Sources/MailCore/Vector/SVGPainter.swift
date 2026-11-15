import Foundation

/// Walks a parsed SVG tree in paint order and collects its shapes, each with its resolved transform and paints.
struct SVGPainter {
    let index: SVGIndex
    let viewBox: VectorRect
    private(set) var shapes: [VectorShape] = []
    /// Set once the document asked for more work than `budget` allows, as nested `use` references multiplying each
    /// other can. The picture is then incomplete and shouldn't be shown.
    private(set) var exhausted = false
    private var visited = 0

    /// Deep enough for any real logo; stops `use` cycles and hostile nesting.
    private static let maximumDepth = 32
    /// Elements painted, counting each `use` of one again: far above any real logo, and small enough to draw within
    /// the notification extension's time and memory.
    static let budget = 10_000

    init(index: SVGIndex, viewBox: VectorRect) {
        self.index = index
        self.viewBox = viewBox
    }

    /// Paints `element` and its children. `transform` maps the parent's coordinates into the view box.
    mutating func paint(
        _ element: SVGElement, style inherited: SVGStyle, transform: VectorTransform, depth: Int,
        referenced: Bool = false
    ) {
        guard !exhausted, depth < Self.maximumDepth else { return }
        visited += 1
        guard visited <= Self.budget else {
            exhausted = true
            return
        }
        guard let style = inherited.child(for: element, sheet: index.sheet) else { return }
        let local = SVGTransformList.transform(element.attributes["transform"]).then(transform)
        switch element.name {
        case "svg":
            // A nested `svg` is placed at its x and y; its own viewBox is ignored.
            let offset =
                depth == 0
                ? VectorTransform.identity
                : .translation(length("x", of: element, along: \.width), length("y", of: element, along: \.height))
            paintChildren(of: element, style: style, transform: offset.then(local), depth: depth)
        case "g", "a", "switch":
            paintChildren(of: element, style: style, transform: local, depth: depth)
        case "symbol" where referenced:
            paintChildren(of: element, style: style, transform: local, depth: depth)
        case "use":
            guard let id = element.reference, let target = index.elements[id] else { return }
            let offset = VectorTransform.translation(
                length("x", of: element, along: \.width), length("y", of: element, along: \.height))
            paint(target, style: style, transform: offset.then(local), depth: depth + 1, referenced: true)
        default:
            guard let path = SVGShapeGeometry.path(of: element, in: viewBox) else { return }
            add(path, filled: element.name != "line", style: style, transform: local)
        }
    }

    private mutating func paintChildren(
        of element: SVGElement, style: SVGStyle, transform: VectorTransform, depth: Int
    ) {
        for child in element.children {
            paint(child, style: style, transform: transform, depth: depth + 1)
        }
    }

    private mutating func add(_ path: [PathSegment], filled: Bool, style: SVGStyle, transform: VectorTransform) {
        guard style.visible, !path.isEmpty else { return }
        let fill = filled ? paint(style.fill, opacity: style.fillOpacity * style.opacity, style: style) : nil
        let stroke =
            style.strokeWidth > 0
            ? paint(style.stroke, opacity: style.strokeOpacity * style.opacity, style: style).map {
                VectorStroke(
                    paint: $0, width: style.strokeWidth, cap: style.cap, join: style.join,
                    miterLimit: style.miterLimit)
            } : nil
        guard fill != nil || stroke != nil else { return }
        shapes.append(
            VectorShape(path: path, transform: transform, fill: fill, fillRule: style.fillRule, stroke: stroke))
    }

    private func paint(_ spec: SVGPaintSpec, opacity: Double, style: SVGStyle) -> VectorPaint? {
        guard opacity > 0 else { return nil }
        switch spec {
        case .none: return nil
        case .color(let color): return .color(color.fading(by: opacity))
        case .currentColor: return .color(style.color.fading(by: opacity))
        case .reference(let id, let fallback):
            return SVGGradients.paint(id, in: index, viewBox: viewBox, opacity: opacity)
                ?? fallback.map { .color($0.fading(by: opacity)) }
        }
    }

    private func length(_ name: String, of element: SVGElement, along side: KeyPath<VectorRect, Double>) -> Double {
        SVGLength.value(element.attributes[name], reference: viewBox[keyPath: side]) ?? 0
    }
}

/// The paths of SVG's basic shapes, in the element's own coordinates.
enum SVGShapeGeometry {
    /// How far along each axis a quarter ellipse's control points sit, as a fraction of the radius.
    private static let kappa = 0.552_284_749_8

    static func path(of element: SVGElement, in viewBox: VectorRect) -> [PathSegment]? {
        func x(_ name: String) -> Double? { SVGLength.value(element.attributes[name], reference: viewBox.width) }
        func y(_ name: String) -> Double? { SVGLength.value(element.attributes[name], reference: viewBox.height) }
        switch element.name {
        case "path":
            return SVGPathData.segments(element.attributes["d"] ?? "")
        case "rect":
            guard let width = x("width"), let height = y("height"), width > 0, height > 0 else { return nil }
            let corner = (x("rx"), y("ry"))
            let rx = min(corner.0 ?? corner.1 ?? 0, width / 2)
            let ry = min(corner.1 ?? corner.0 ?? 0, height / 2)
            return rect(VectorRect(x: x("x") ?? 0, y: y("y") ?? 0, width: width, height: height), rx: rx, ry: ry)
        case "circle":
            guard let r = x("r"), r > 0 else { return nil }
            return ellipse(center: VectorPoint(x: x("cx") ?? 0, y: y("cy") ?? 0), rx: r, ry: r)
        case "ellipse":
            guard let rx = x("rx"), let ry = y("ry"), rx > 0, ry > 0 else { return nil }
            return ellipse(center: VectorPoint(x: x("cx") ?? 0, y: y("cy") ?? 0), rx: rx, ry: ry)
        case "line":
            return [
                .move(VectorPoint(x: x("x1") ?? 0, y: y("y1") ?? 0)),
                .line(VectorPoint(x: x("x2") ?? 0, y: y("y2") ?? 0)),
            ]
        case "polyline", "polygon":
            var scanner = NumberScanner(element.attributes["points"] ?? "")
            let values = scanner.numbers()
            let points = stride(from: 0, to: values.count - 1, by: 2).map {
                VectorPoint(x: values[$0], y: values[$0 + 1])
            }
            guard let first = points.first else { return nil }
            let lines = [PathSegment.move(first)] + points.dropFirst().map(PathSegment.line)
            return element.name == "polygon" ? lines + [.close] : lines
        default:
            return nil
        }
    }

    private static func rect(_ frame: VectorRect, rx: Double, ry: Double) -> [PathSegment] {
        let (left, top) = (frame.x, frame.y)
        let (right, bottom) = (frame.x + frame.width, frame.y + frame.height)
        func p(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }
        guard rx > 0, ry > 0 else {
            return [.move(p(left, top)), .line(p(right, top)), .line(p(right, bottom)), .line(p(left, bottom)), .close]
        }
        let (kx, ky) = (rx * kappa, ry * kappa)
        return [
            .move(p(left + rx, top)),
            .line(p(right - rx, top)),
            .cubic(control1: p(right - rx + kx, top), control2: p(right, top + ry - ky), to: p(right, top + ry)),
            .line(p(right, bottom - ry)),
            .cubic(
                control1: p(right, bottom - ry + ky), control2: p(right - rx + kx, bottom), to: p(right - rx, bottom)),
            .line(p(left + rx, bottom)),
            .cubic(control1: p(left + rx - kx, bottom), control2: p(left, bottom - ry + ky), to: p(left, bottom - ry)),
            .line(p(left, top + ry)),
            .cubic(control1: p(left, top + ry - ky), control2: p(left + rx - kx, top), to: p(left + rx, top)),
            .close,
        ]
    }

    private static func ellipse(center: VectorPoint, rx: Double, ry: Double) -> [PathSegment] {
        let (cx, cy, kx, ky) = (center.x, center.y, rx * kappa, ry * kappa)
        func p(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }
        return [
            .move(p(cx + rx, cy)),
            .cubic(control1: p(cx + rx, cy + ky), control2: p(cx + kx, cy + ry), to: p(cx, cy + ry)),
            .cubic(control1: p(cx - kx, cy + ry), control2: p(cx - rx, cy + ky), to: p(cx - rx, cy)),
            .cubic(control1: p(cx - rx, cy - ky), control2: p(cx - kx, cy - ry), to: p(cx, cy - ry)),
            .cubic(control1: p(cx + kx, cy - ry), control2: p(cx + rx, cy - ky), to: p(cx + rx, cy)),
            .close,
        ]
    }
}

/// SVG's `transform` attribute: a list of `matrix`, `translate`, `scale`, `rotate`, `skewX` and `skewY`.
enum SVGTransformList {
    /// The list as one transform, or the identity for none. A malformed list is ignored as a whole.
    static func transform(_ text: String?) -> VectorTransform {
        guard let text, !text.isEmpty else { return .identity }
        var steps: [VectorTransform] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\t\n\r"))
            var scanner = NumberScanner(String(rest[rest.index(after: open)..<close]))
            guard let step = step(name, scanner.numbers()) else { return .identity }
            steps.append(step)
            rest = rest[rest.index(after: close)...]
        }
        // The rightmost transform applies to the shape first.
        return steps.reversed().reduce(VectorTransform.identity) { $0.then($1) }
    }

    private static func step(_ name: String, _ v: [Double]) -> VectorTransform? {
        switch (name, v.count) {
        case ("matrix", 6): return VectorTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        case ("translate", 1): return .translation(v[0], 0)
        case ("translate", 2): return .translation(v[0], v[1])
        case ("scale", 1): return .scale(v[0], v[0])
        case ("scale", 2): return .scale(v[0], v[1])
        case ("rotate", 1), ("rotate", 3):
            let angle = v[0] * .pi / 180
            let rotation = VectorTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: 0, ty: 0)
            guard v.count == 3 else { return rotation }
            return VectorTransform.translation(-v[1], -v[2]).then(rotation).then(.translation(v[1], v[2]))
        case ("skewX", 1): return VectorTransform(a: 1, b: 0, c: tan(v[0] * .pi / 180), d: 1, tx: 0, ty: 0)
        case ("skewY", 1): return VectorTransform(a: 1, b: tan(v[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
        default: return nil
        }
    }
}
