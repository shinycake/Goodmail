/// A picture made of filled and stroked paths, as an SVG logo becomes once parsed: a value that draws crisply at any
/// size and crosses actors freely.
public struct VectorImage: Sendable, Equatable {
    /// The area of user space the picture shows.
    public var viewBox: VectorRect
    /// Painted in order, later shapes over earlier ones.
    public var shapes: [VectorShape]

    public init(viewBox: VectorRect, shapes: [VectorShape]) {
        self.viewBox = viewBox
        self.shapes = shapes
    }
}

public struct VectorPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct VectorRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// An affine map in SVG's `matrix(a b c d e f)` form: x' = a·x + c·y + tx, y' = b·x + d·y + ty.
public struct VectorTransform: Sendable, Equatable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = VectorTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    static func translation(_ x: Double, _ y: Double) -> VectorTransform {
        VectorTransform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    static func scale(_ x: Double, _ y: Double) -> VectorTransform {
        VectorTransform(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    /// `self` applied inside `outer`: the map that first applies `self`, then `outer`. A child's transform is
    /// prepended to its parent's this way.
    public func then(_ outer: VectorTransform) -> VectorTransform {
        VectorTransform(
            a: a * outer.a + b * outer.c, b: a * outer.b + b * outer.d,
            c: c * outer.a + d * outer.c, d: c * outer.b + d * outer.d,
            tx: tx * outer.a + ty * outer.c + outer.tx, ty: tx * outer.b + ty * outer.d + outer.ty)
    }

    public func apply(to point: VectorPoint) -> VectorPoint {
        VectorPoint(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
    }
}

/// One step of a path, in absolute coordinates. Arcs and smooth curves are already turned into these.
public enum PathSegment: Sendable, Equatable {
    case move(VectorPoint)
    case line(VectorPoint)
    case quadratic(control: VectorPoint, to: VectorPoint)
    case cubic(control1: VectorPoint, control2: VectorPoint, to: VectorPoint)
    case close
}

/// A path with its paint, in the coordinates `transform` maps into the view box.
public struct VectorShape: Sendable, Equatable {
    public enum FillRule: Sendable, Equatable {
        case nonZero, evenOdd
    }

    public var path: [PathSegment]
    public var transform: VectorTransform
    public var fill: VectorPaint?
    public var fillRule: FillRule
    public var stroke: VectorStroke?

    public init(
        path: [PathSegment], transform: VectorTransform = .identity, fill: VectorPaint?,
        fillRule: FillRule = .nonZero, stroke: VectorStroke? = nil
    ) {
        self.path = path
        self.transform = transform
        self.fill = fill
        self.fillRule = fillRule
        self.stroke = stroke
    }
}

public struct VectorStroke: Sendable, Equatable {
    public enum Cap: Sendable, Equatable {
        case butt, round, square
    }

    public enum Join: Sendable, Equatable {
        case miter, round, bevel
    }

    public var paint: VectorPaint
    public var width: Double
    public var cap: Cap
    public var join: Join
    public var miterLimit: Double

    public init(paint: VectorPaint, width: Double, cap: Cap = .butt, join: Join = .miter, miterLimit: Double = 4) {
        self.paint = paint
        self.width = width
        self.cap = cap
        self.join = join
        self.miterLimit = miterLimit
    }
}

/// What fills or strokes a shape. Opacities are already folded into the colors' alpha.
public enum VectorPaint: Sendable, Equatable {
    case color(VectorColor)
    case linearGradient(LinearGradient)
    case radialGradient(RadialGradient)
}

/// An sRGB color with straight (not premultiplied) alpha, each component from 0 to 1.
public struct VectorColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = VectorColor(red: 0, green: 0, blue: 0)

    func fading(by opacity: Double) -> VectorColor {
        VectorColor(red: red, green: green, blue: blue, alpha: alpha * opacity)
    }
}

public struct GradientStop: Sendable, Equatable {
    /// From 0 to 1, never less than the stop before it.
    public var offset: Double
    public var color: VectorColor

    public init(offset: Double, color: VectorColor) {
        self.offset = offset
        self.color = color
    }
}

/// Whether a gradient's points are fractions of the painted shape's bounds, or user-space coordinates.
public enum GradientUnits: Sendable, Equatable {
    case objectBoundingBox, userSpaceOnUse
}

public struct LinearGradient: Sendable, Equatable {
    public var start: VectorPoint
    public var end: VectorPoint
    public var stops: [GradientStop]
    public var units: GradientUnits
    public var transform: VectorTransform

    public init(
        start: VectorPoint, end: VectorPoint, stops: [GradientStop], units: GradientUnits,
        transform: VectorTransform = .identity
    ) {
        self.start = start
        self.end = end
        self.stops = stops
        self.units = units
        self.transform = transform
    }
}

public struct RadialGradient: Sendable, Equatable {
    public var center: VectorPoint
    public var radius: Double
    public var focus: VectorPoint
    public var stops: [GradientStop]
    public var units: GradientUnits
    public var transform: VectorTransform

    public init(
        center: VectorPoint, radius: Double, focus: VectorPoint, stops: [GradientStop], units: GradientUnits,
        transform: VectorTransform = .identity
    ) {
        self.center = center
        self.radius = radius
        self.focus = focus
        self.stops = stops
        self.units = units
        self.transform = transform
    }
}
