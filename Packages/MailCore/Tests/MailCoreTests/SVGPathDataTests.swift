import Testing

@testable import MailCore

struct SVGPathDataTests {
    private func p(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

    @Test func relativeCommandsAndImplicitLinesBecomeAbsolute() {
        #expect(
            SVGPathData.segments("m10 20 5 5h10v-5Z")
                == [.move(p(10, 20)), .line(p(15, 25)), .line(p(25, 25)), .line(p(25, 20)), .close])
    }

    @Test func compactNumbersSplitWhereAnotherNumberStarts() {
        // Illustrator writes "c.2-12.5" and ".5.5" with no separators.
        #expect(
            SVGPathData.segments("M0,0c.2-12.5-1.8-24.6-5.9-35.7")
                == [.move(p(0, 0)), .cubic(control1: p(0.2, -12.5), control2: p(-1.8, -24.6), to: p(-5.9, -35.7))])
        #expect(SVGPathData.segments("M.5.5L1e1-2E-1") == [.move(p(0.5, 0.5)), .line(p(10, -0.2))])
    }

    @Test func smoothCurvesReflectThePreviousControlPoint() {
        #expect(
            SVGPathData.segments("M0 0C0 10 10 10 10 0S20 -10 20 0")
                == [
                    .move(p(0, 0)), .cubic(control1: p(0, 10), control2: p(10, 10), to: p(10, 0)),
                    .cubic(control1: p(10, -10), control2: p(20, -10), to: p(20, 0)),
                ])
        #expect(
            SVGPathData.segments("M0 0Q5 5 10 0T20 0")
                == [
                    .move(p(0, 0)), .quadratic(control: p(5, 5), to: p(10, 0)),
                    .quadratic(control: p(15, -5), to: p(20, 0)),
                ])
    }

    @Test func arcsBecomeCubicsThatEndExactlyAtTheEndpoint() throws {
        // Packed flags: "a10 10 0 00 20 0" is rx 10, ry 10, rotation 0, large-arc 0, sweep 0, to (20, 0).
        let segments = SVGPathData.segments("M0 0a10 10 0 00 20 0")
        #expect(segments.count == 3)
        guard case .cubic(_, _, let end) = try #require(segments.last) else {
            Issue.record("Expected a cubic, got \(segments)")
            return
        }
        #expect(end == p(20, 0))
    }

    @Test func aHalfCircleArcPassesThroughItsMidpoint() throws {
        let segments = SVGPathData.segments("M0 0A10 10 0 0 1 20 0")
        guard case .cubic(_, _, let middle) = segments[1] else {
            Issue.record("Expected a cubic, got \(segments)")
            return
        }
        // Sweeping clockwise in SVG's y-down space from (0,0) to (20,0) passes over the top, at y = -10.
        #expect(abs(middle.x - 10) < 1e-9)
        #expect(abs(middle.y + 10) < 1e-9)
    }

    @Test func malformedDataDrawsUpToItsFirstError() {
        #expect(SVGPathData.segments("M0 0L10 10L20") == [.move(p(0, 0)), .line(p(10, 10))])
        #expect(SVGPathData.segments("10 10 L20 20").isEmpty)
        #expect(SVGPathData.segments("L20 20").isEmpty)
        #expect(SVGPathData.segments("M0 0Z 5 5") == [.move(p(0, 0)), .close])
    }
}
