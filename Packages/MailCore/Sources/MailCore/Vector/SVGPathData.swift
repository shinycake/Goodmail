import Foundation

/// SVG path data (`d="M10 20 L30 40 Z"`) as absolute segments. Relative, shorthand, smooth and arc commands become
/// lines and curves. Malformed data renders up to its first error, as SVG requires.
enum SVGPathData {
    static func segments(_ data: String) -> [PathSegment] {
        var reader = PathReader(data)
        return reader.read()
    }
}

/// Reads one path's data, tracking the pen and the last control point that smooth curves reflect.
private struct PathReader {
    private var scanner: NumberScanner
    private var segments: [PathSegment] = []
    private var pen = VectorPoint(x: 0, y: 0)
    private var subpathStart = VectorPoint(x: 0, y: 0)
    /// The last curve's final control point, which a following `S` or `T` reflects.
    private var lastControl: LastControl = .none

    private enum LastControl {
        case none
        case cubic(VectorPoint)
        case quadratic(VectorPoint)
    }

    init(_ data: String) {
        scanner = NumberScanner(data)
    }

    mutating func read() -> [PathSegment] {
        var command: Character?
        while true {
            scanner.skipSeparators()
            guard let next = scanner.peek else { break }
            if next.isLetter {
                // A path must start with a move.
                if segments.isEmpty, next != "M", next != "m" { break }
                scanner.advance()
                command = next
                // Commands without arguments run once; a number after one is an error.
                if next == "Z" || next == "z" {
                    close()
                    command = nil
                    continue
                }
            } else if command == nil {
                break  // a number with no command, or after Z
            }
            guard let current = command, step(current) else { break }
            // After a move, further coordinate pairs are lines.
            if current == "M" { command = "L" } else if current == "m" { command = "l" }
        }
        return segments
    }

    /// Reads one set of `command`'s arguments and adds its segment. `false` when they are malformed.
    private mutating func step(_ command: Character) -> Bool {
        let relative = command.isLowercase
        let origin = relative ? pen : VectorPoint(x: 0, y: 0)
        func point(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: origin.x + x, y: origin.y + y) }

        switch command.uppercased() {
        case "M":
            guard let (x, y) = pair() else { return false }
            pen = point(x, y)
            subpathStart = pen
            segments.append(.move(pen))
            lastControl = .none
        case "L":
            guard let (x, y) = pair() else { return false }
            line(to: point(x, y))
        case "H":
            guard let x = scanner.number() else { return false }
            line(to: VectorPoint(x: relative ? pen.x + x : x, y: pen.y))
        case "V":
            guard let y = scanner.number() else { return false }
            line(to: VectorPoint(x: pen.x, y: relative ? pen.y + y : y))
        case "C":
            guard let (x1, y1) = pair(), let (x2, y2) = pair(), let (x, y) = pair() else { return false }
            cubic(point(x1, y1), point(x2, y2), point(x, y))
        case "S":
            guard let (x2, y2) = pair(), let (x, y) = pair() else { return false }
            let first: VectorPoint
            if case .cubic(let control) = lastControl { first = reflect(control) } else { first = pen }
            cubic(first, point(x2, y2), point(x, y))
        case "Q":
            guard let (x1, y1) = pair(), let (x, y) = pair() else { return false }
            quadratic(point(x1, y1), point(x, y))
        case "T":
            guard let (x, y) = pair() else { return false }
            let control: VectorPoint
            if case .quadratic(let last) = lastControl { control = reflect(last) } else { control = pen }
            quadratic(control, point(x, y))
        case "A":
            guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                let large = scanner.flag(), let sweep = scanner.flag(), let (x, y) = pair()
            else { return false }
            let end = point(x, y)
            for curve in SVGArc.cubics(
                from: pen, to: end, radii: (abs(rx), abs(ry)), rotation: rotation, largeArc: large, sweep: sweep)
            {
                segments.append(curve)
            }
            if pen != end, rx == 0 || ry == 0 { segments.append(.line(end)) }
            pen = end
            lastControl = .none
        default:
            return false
        }
        return true
    }

    private mutating func pair() -> (Double, Double)? {
        guard let x = scanner.number(), let y = scanner.number() else { return nil }
        return (x, y)
    }

    private func reflect(_ control: VectorPoint) -> VectorPoint {
        VectorPoint(x: 2 * pen.x - control.x, y: 2 * pen.y - control.y)
    }

    private mutating func line(to point: VectorPoint) {
        segments.append(.line(point))
        pen = point
        lastControl = .none
    }

    private mutating func cubic(_ control1: VectorPoint, _ control2: VectorPoint, _ end: VectorPoint) {
        segments.append(.cubic(control1: control1, control2: control2, to: end))
        pen = end
        lastControl = .cubic(control2)
    }

    private mutating func quadratic(_ control: VectorPoint, _ end: VectorPoint) {
        segments.append(.quadratic(control: control, to: end))
        pen = end
        lastControl = .quadratic(control)
    }

    private mutating func close() {
        segments.append(.close)
        pen = subpathStart
        lastControl = .none
    }
}

/// Reads SVG's compact number lists, where `1.5.5-2e1` is three numbers and separators are optional.
struct NumberScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    var peek: Character? { index < characters.count ? characters[index] : nil }

    mutating func advance() { index += 1 }

    mutating func skipSeparators() {
        while let next = peek, next.isWhitespace || next == "," { advance() }
    }

    /// The next number, or `nil` (consuming nothing) when there isn't one.
    mutating func number() -> Double? {
        skipSeparators()
        let start = index
        if peek == "+" || peek == "-" { advance() }
        var digits = 0
        while let next = peek, next.isASCII, next.isNumber {
            advance()
            digits += 1
        }
        if peek == "." {
            advance()
            while let next = peek, next.isASCII, next.isNumber {
                advance()
                digits += 1
            }
        }
        guard digits > 0 else {
            index = start
            return nil
        }
        if peek == "e" || peek == "E" {
            let mantissaEnd = index
            advance()
            if peek == "+" || peek == "-" { advance() }
            var exponentDigits = 0
            while let next = peek, next.isASCII, next.isNumber {
                advance()
                exponentDigits += 1
            }
            if exponentDigits == 0 { index = mantissaEnd }
        }
        return Double(String(characters[start..<index]))
    }

    /// An arc flag: a single `0` or `1`, which may run straight into the next number.
    mutating func flag() -> Bool? {
        skipSeparators()
        switch peek {
        case "0":
            advance()
            return false
        case "1":
            advance()
            return true
        default: return nil
        }
    }

    /// Every number left, as in `points` and `viewBox` lists. Stops at the first thing that isn't one.
    mutating func numbers() -> [Double] {
        var values: [Double] = []
        while let value = number() { values.append(value) }
        return values
    }
}
