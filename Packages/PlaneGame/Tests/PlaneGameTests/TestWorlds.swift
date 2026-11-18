import Foundation

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A phone-sized field whose travel from ceiling to row is 640 points, so its pace is 1 and speeds are the rules' own.
let phoneField = PlaneGameField(size: CGSize(width: 400, height: 860), lanes: 12...388, ceiling: 80, row: 720)

/// The fields of an iPhone held upright and turned on its side, and of a small iPad window.
let windowFields = [
    PlaneGameField(size: CGSize(width: 402, height: 874), safeTop: 62, safeLeft: 0, safeBottom: 34, safeRight: 0),
    PlaneGameField(size: CGSize(width: 874, height: 402), safeTop: 0, safeLeft: 62, safeBottom: 21, safeRight: 62),
    PlaneGameField(size: CGSize(width: 374, height: 482), safeTop: 24, safeLeft: 0, safeBottom: 20, safeRight: 0),
]

/// One display frame, the longest step the world takes in one go.
let frame = PlaneGameRules.longestStep

extension PlaneGameWorld {
    /// A world whose plane has finished its launch and is flying at its starting place. Unless `arrivals` is true,
    /// nothing arrives, so a test can place exactly what it needs.
    static func flying(on field: PlaneGameField = phoneField, seed: UInt64 = 1, arrivals: Bool = false)
        -> PlaneGameWorld
    {
        var world = PlaneGameWorld(field: field, launch: .inPlace, after: 0, seed: seed)
        if !arrivals { world.spawner.close() }
        world.run(for: FlightPath.duration + frame)
        return world
    }

    /// Steps the world frame by frame for `seconds` with the same input every frame, and gathers what happened.
    @discardableResult
    mutating func run(for seconds: TimeInterval, input: PlaneGameInput = PlaneGameInput()) -> [PlaneGameEvent] {
        var events: [PlaneGameEvent] = []
        for _ in 0..<Int((seconds / frame).rounded()) {
            events += advance(by: frame, input: input)
        }
        return events
    }

    /// Puts a thing of `kind` this far above the plane.
    mutating func addAhead(_ kind: PlaneGameThing.Kind, by offset: CGFloat = 0) {
        add(kind, at: CGPoint(x: plane.position.x, y: plane.position.y - offset))
    }
}
