import Foundation
import PlaneGame
import Testing

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The loop the plane flies onto the field when it sets off.
struct LoopPathTests {
    static let directions = [
        (CGPoint(x: -40, y: 420), CGPoint(x: 88, y: 360)),
        (CGPoint(x: 300, y: 500), CGPoint(x: 88, y: 360)),
    ]

    @Test(arguments: directions)
    func endsWhereItSays(start: CGPoint, end: CGPoint) {
        let path = LoopPath(from: start, to: end)
        #expect(path.point(at: 0) == start)
        #expect(path.point(at: 1) == end)
        #expect(path.point(at: -0.5) == start)
        #expect(path.point(at: 1.5) == end)
    }

    @Test(arguments: directions)
    func neverJumps(start: CGPoint, end: CGPoint) {
        let path = LoopPath(from: start, to: end)
        let length = hypot(end.x - start.x, end.y - start.y) + 2 * .pi * LoopPath.loopRadius
        for step in 0..<100 {
            let here = path.point(at: Double(step) / 100)
            let next = path.point(at: Double(step + 1) / 100)
            #expect(hypot(next.x - here.x, next.y - here.y) <= length / 10)
        }
    }

    @Test(arguments: directions)
    func setsOffTowardItsEndAndLoopsUpward(start: CGPoint, end: CGPoint) {
        let path = LoopPath(from: start, to: end)
        let towardEnd = end.x > start.x ? 1.0 : -1.0
        #expect(cos(path.heading(at: 0)) * towardEnd > 0)
        let highest = (0...100).map { path.point(at: Double($0) / 100).y }.min() ?? 0
        #expect(highest < (start.y + end.y) / 2 - LoopPath.loopRadius)
    }
}
