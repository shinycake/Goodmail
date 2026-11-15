import Foundation

/// Gradient paint servers, with the attributes and stops they inherit through `href` chains.
enum SVGGradients {
    /// How far an `href` chain is followed, which also stops cycles.
    private static let maximumChain = 8

    /// The gradient `id` names, faded by `opacity`: a solid color when it has one stop, `nil` when it has none or
    /// isn't a gradient.
    static func paint(_ id: String, in index: SVGIndex, viewBox: VectorRect, opacity: Double) -> VectorPaint? {
        let chain = self.chain(from: id, in: index)
        guard let gradient = chain.first, ["linearGradient", "radialGradient"].contains(gradient.name) else {
            return nil
        }
        let stops = self.stops(in: chain, sheet: index.sheet).map {
            GradientStop(offset: $0.offset, color: $0.color.fading(by: opacity))
        }
        guard let first = stops.first else { return nil }
        guard stops.count > 1 else { return .color(first.color) }

        func attribute(_ name: String) -> String? { chain.lazy.compactMap { $0.attributes[name] }.first }
        let units: GradientUnits = attribute("gradientUnits") == "userSpaceOnUse" ? .userSpaceOnUse : .objectBoundingBox
        func x(_ name: String, _ fallback: String) -> Double {
            SVGLength.value(attribute(name) ?? fallback, reference: units == .userSpaceOnUse ? viewBox.width : 1) ?? 0
        }
        func y(_ name: String, _ fallback: String) -> Double {
            SVGLength.value(attribute(name) ?? fallback, reference: units == .userSpaceOnUse ? viewBox.height : 1)
                ?? 0
        }
        let transform = SVGTransformList.transform(attribute("gradientTransform"))
        if gradient.name == "linearGradient" {
            return .linearGradient(
                LinearGradient(
                    start: VectorPoint(x: x("x1", "0%"), y: y("y1", "0%")),
                    end: VectorPoint(x: x("x2", "100%"), y: y("y2", "0%")), stops: stops, units: units,
                    transform: transform))
        }
        let center = VectorPoint(x: x("cx", "50%"), y: y("cy", "50%"))
        let radius = x("r", "50%")
        guard radius > 0 else { return .color(stops[stops.count - 1].color) }
        let focus = VectorPoint(
            x: attribute("fx").flatMap { SVGLength.value($0, reference: units == .userSpaceOnUse ? viewBox.width : 1) }
                ?? center.x,
            y: attribute("fy").flatMap {
                SVGLength.value($0, reference: units == .userSpaceOnUse ? viewBox.height : 1)
            } ?? center.y)
        return .radialGradient(
            RadialGradient(
                center: center, radius: radius, focus: focus, stops: stops, units: units, transform: transform))
    }

    /// The gradient and the gradients it inherits from, nearest first.
    private static func chain(from id: String, in index: SVGIndex) -> [SVGElement] {
        var chain: [SVGElement] = []
        var next: String? = id
        while let id = next, chain.count < maximumChain, let element = index.elements[id] {
            chain.append(element)
            next = element.reference
        }
        return chain
    }

    /// The stops of the nearest gradient in the chain that has any, with offsets clamped to rise from 0 to 1.
    private static func stops(in chain: [SVGElement], sheet: SVGStyleSheet) -> [GradientStop] {
        guard let owner = chain.first(where: { $0.children.contains { $0.name == "stop" } }) else { return [] }
        var floor = 0.0
        return owner.children.filter { $0.name == "stop" }.map { stop in
            let declarations = SVGStyle.declarations(of: stop, sheet: sheet)
            let offset = max(floor, min(1, max(0, SVGLength.value(stop.attributes["offset"]) ?? 0)))
            floor = offset
            let color = declarations["stop-color"].flatMap(SVGColor.color) ?? .black
            let opacity = declarations["stop-opacity"].flatMap(SVGStyle.fraction) ?? 1
            return GradientStop(offset: offset, color: color.fading(by: opacity))
        }
    }
}
