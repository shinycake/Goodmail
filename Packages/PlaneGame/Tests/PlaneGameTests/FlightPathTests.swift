import Foundation
import PlaneGame
import Testing

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The paths the plane flies onto the field and home to the envelopes.
struct FlightPathTests {
    /// Where the envelopes might be when the plane unfolds from them: the middle of the window and well to each side.
    private static func starts(in field: PlaneGameField) -> [CGPoint] {
        let size = field.size
        return [
            CGPoint(x: size.width / 2, y: size.height * 0.35), CGPoint(x: size.width * 0.2, y: size.height * 0.3),
            CGPoint(x: size.width * 0.8, y: size.height * 0.5),
        ]
    }

    /// Every launch from the envelopes to the starting place, in each window.
    private static let launches = windowFields.flatMap { field in
        starts(in: field).map { (field, FlightPath.launch(from: $0, to: field.startingPlace, lanes: field.lanes)) }
    }

    /// One of each kind of path.
    private static let paths: [FlightPath] = [
        .launch(from: CGPoint(x: 201, y: 306), to: CGPoint(x: 201, y: 720), lanes: 12...390),
        .landing(from: CGPoint(x: 90, y: 720), to: CGPoint(x: 201, y: 306)),
        .straight(from: CGPoint(x: 201, y: 934), to: CGPoint(x: 201, y: 720)),
    ]

    @Test(arguments: paths)
    func endsExactlyWhereItSays(path: FlightPath) {
        #expect(path.point(at: 0) == path.start)
        #expect(path.point(at: 1) == path.end)
        #expect(path.point(at: -0.5) == path.start)
        #expect(path.point(at: 1.5) == path.end)
    }

    @Test(arguments: paths)
    func neverJumps(path: FlightPath) {
        // The curve is never longer than the lines between its four points.
        let corners = [
            path.start, CGPoint(x: path.start.x + path.leaving.x, y: path.start.y + path.leaving.y),
            CGPoint(x: path.end.x + path.arriving.x, y: path.end.y + path.arriving.y), path.end,
        ]
        let longest = zip(corners, corners.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }.reduce(0, +)
        for step in 0..<100 {
            let here = path.point(at: Double(step) / 100)
            let next = path.point(at: Double(step + 1) / 100)
            #expect(hypot(next.x - here.x, next.y - here.y) <= longest / 10)
        }
    }

    @Test(arguments: launches)
    func aLaunchEndsInItsPlacePointingUp(field: PlaneGameField, path: FlightPath) {
        #expect(path.end == field.startingPlace)
        #expect(path.heading(at: 1) == 0)
    }

    @Test(arguments: launches)
    func aLaunchGoesNoFartherThanItsReachOutsideTheWindow(field: PlaneGameField, path: FlightPath) {
        let reach = FlightPath.reach(from: path.start, to: path.end)
        let allowed = CGRect(origin: .zero, size: field.size).insetBy(dx: -reach, dy: -reach)
        for step in 0...200 {
            #expect(allowed.contains(path.point(at: Double(step) / 200)))
        }
    }

    @Test(arguments: launches)
    func aLaunchSetsOffUpAndTowardTheSideWithMoreRoom(field: PlaneGameField, path: FlightPath) {
        let roomRight = field.lanes.upperBound - path.start.x
        let roomLeft = path.start.x - field.lanes.lowerBound
        let heading = path.heading(at: 0)
        #expect(cos(heading) > 0)
        #expect(roomRight >= roomLeft ? sin(heading) > 0 : sin(heading) < 0)
    }

    @Test(arguments: launches)
    func aLaunchComesUpIntoItsPlaceFromUnderTheRow(field: PlaneGameField, path: FlightPath) {
        let nearlyThere = path.point(at: 0.97)
        #expect(nearlyThere.y > field.row)
        #expect(abs(nearlyThere.x - path.end.x) < 1)
    }

    @Test(arguments: [CGPoint(x: 90, y: 720), CGPoint(x: 320, y: 720)])
    func theLandingLeavesStraightUpAndComesInFromBelowOnItsSide(from start: CGPoint) {
        let home = CGPoint(x: 201, y: 306)
        let path = FlightPath.landing(from: start, to: home)
        #expect(path.heading(at: 0) == 0)
        let nearlyThere = path.point(at: 0.97)
        #expect(nearlyThere.y > home.y)
        #expect(start.x < home.x ? nearlyThere.x < home.x : nearlyThere.x > home.x)
    }

    @Test func aStraightPathHoldsItsLineAndHeading() {
        let path = FlightPath.straight(from: CGPoint(x: 201, y: 934), to: CGPoint(x: 201, y: 720))
        for step in 0...20 {
            #expect(path.point(at: Double(step) / 20).x == 201)
            #expect(abs(path.heading(at: Double(step) / 20)) < 0.000_001)
        }
    }

    @Test func aStraightPathFromAPointToItselfHoldsStill() {
        let here = CGPoint(x: 201, y: 720)
        let path = FlightPath.straight(from: here, to: here)
        #expect((0...10).allSatisfy { path.point(at: Double($0) / 10) == here })
        #expect(path.heading(at: 0.5) == 0)
    }

    @Test func movingItsEndKeepsItsStartAndHandles() {
        let path = FlightPath.landing(from: CGPoint(x: 90, y: 720), to: CGPoint(x: 201, y: 306))
        let moved = path.ending(at: CGPoint(x: 500, y: 200))
        #expect(moved.start == path.start)
        #expect(moved.leaving == path.leaving)
        #expect(moved.arriving == path.arriving)
        #expect(moved.point(at: 1) == CGPoint(x: 500, y: 200))
    }

    @Test func theReachIsHalfTheWayBetweenEightyAndOneSixty() {
        #expect(FlightPath.reach(from: .zero, to: CGPoint(x: 0, y: 100)) == 80)
        #expect(FlightPath.reach(from: .zero, to: CGPoint(x: 0, y: 240)) == 120)
        #expect(FlightPath.reach(from: .zero, to: CGPoint(x: 0, y: 900)) == 160)
    }
}
