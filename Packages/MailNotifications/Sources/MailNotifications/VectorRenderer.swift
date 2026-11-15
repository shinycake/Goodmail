import CoreGraphics
import Foundation
import ImageIO
import MailCore

/// Draws a `VectorImage` into a square PNG with Core Graphics, so it works in the notification extension without
/// UIKit.
public enum VectorRenderer {
    /// The picture fitted and centered in a `side`-pixel square on white, as SVG's default `xMidYMid meet` places
    /// it, or `nil` when it can't be drawn.
    public static func png(of image: VectorImage, side: Int) -> Data? {
        let box = image.viewBox
        guard side > 0, box.width > 0, box.height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let size = Double(side)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        // Core Graphics counts y up from the bottom; SVG counts it down from the top.
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        let scale = min(size / box.width, size / box.height)
        context.translateBy(x: (size - box.width * scale) / 2, y: (size - box.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.x, y: -box.y)
        for shape in image.shapes {
            draw(shape, in: context, space: space)
        }
        guard let rendered = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func draw(_ shape: VectorShape, in context: CGContext, space: CGColorSpace) {
        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(CGAffineTransform(shape.transform))
        let path = cgPath(shape.path)
        let rule: CGPathFillRule = shape.fillRule == .evenOdd ? .evenOdd : .winding
        if let fill = shape.fill {
            context.saveGState()
            context.addPath(path)
            if case .color(let color) = fill {
                context.setFillColor(cgColor(color))
                context.fillPath(using: rule)
            } else {
                context.clip(using: rule)
                drawGradient(fill, over: path.boundingBoxOfPath, in: context, space: space)
            }
            context.restoreGState()
        }
        if let stroke = shape.stroke {
            context.saveGState()
            context.setLineWidth(stroke.width)
            context.setLineCap([.butt: .butt, .round: .round, .square: .square][stroke.cap] ?? .butt)
            context.setLineJoin([.miter: .miter, .round: .round, .bevel: .bevel][stroke.join] ?? .miter)
            context.setMiterLimit(stroke.miterLimit)
            context.addPath(path)
            if case .color(let color) = stroke.paint {
                context.setStrokeColor(cgColor(color))
                context.strokePath()
            } else {
                context.replacePathWithStrokedPath()
                context.clip()
                drawGradient(stroke.paint, over: path.boundingBoxOfPath, in: context, space: space)
            }
            context.restoreGState()
        }
    }

    /// Fills the clip with a gradient whose bounding-box units are fractions of `bounds`.
    private static func drawGradient(
        _ paint: VectorPaint, over bounds: CGRect, in context: CGContext, space: CGColorSpace
    ) {
        let stops: [GradientStop]
        let units: GradientUnits
        let transform: VectorTransform
        switch paint {
        case .color: return
        case .linearGradient(let gradient):
            (stops, units, transform) = (gradient.stops, gradient.units, gradient.transform)
        case .radialGradient(let gradient):
            (stops, units, transform) = (gradient.stops, gradient.units, gradient.transform)
        }
        let components = stops.flatMap { [$0.color.red, $0.color.green, $0.color.blue, $0.color.alpha] }.map {
            CGFloat($0)
        }
        guard
            let gradient = CGGradient(
                colorSpace: space, colorComponents: components, locations: stops.map { CGFloat($0.offset) },
                count: stops.count)
        else { return }
        if units == .objectBoundingBox {
            // SVG doesn't paint a bounding-box gradient on a shape without area.
            guard bounds.width > 0, bounds.height > 0 else { return }
            context.concatenate(
                CGAffineTransform(a: bounds.width, b: 0, c: 0, d: bounds.height, tx: bounds.minX, ty: bounds.minY))
        }
        context.concatenate(CGAffineTransform(transform))
        let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch paint {
        case .color: break
        case .linearGradient(let linear):
            context.drawLinearGradient(
                gradient, start: CGPoint(linear.start), end: CGPoint(linear.end), options: options)
        case .radialGradient(let radial):
            context.drawRadialGradient(
                gradient, startCenter: CGPoint(radial.focus), startRadius: 0, endCenter: CGPoint(radial.center),
                endRadius: radial.radius, options: options)
        }
    }

    private static func cgPath(_ segments: [PathSegment]) -> CGPath {
        let path = CGMutablePath()
        for segment in segments {
            switch segment {
            case .move(let point): path.move(to: CGPoint(point))
            case .line(let point): path.addLine(to: CGPoint(point))
            case .quadratic(let control, let end): path.addQuadCurve(to: CGPoint(end), control: CGPoint(control))
            case .cubic(let control1, let control2, let end):
                path.addCurve(to: CGPoint(end), control1: CGPoint(control1), control2: CGPoint(control2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    private static func cgColor(_ color: VectorColor) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension CGPoint {
    fileprivate init(_ point: VectorPoint) {
        self.init(x: point.x, y: point.y)
    }
}

extension CGAffineTransform {
    fileprivate init(_ transform: VectorTransform) {
        self.init(a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: transform.tx, ty: transform.ty)
    }
}
