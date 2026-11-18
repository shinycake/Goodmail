import Foundation

@testable import PlaneGame

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A phone-sized field with room for the HUD above and the home indicator below.
let phoneField = PlaneGameField(size: CGSize(width: 400, height: 800), band: 80...760)

/// One display frame, the longest step the world takes in one go.
let frame = PlaneGameRules.longestStep

extension PlaneGameWorld {
    /// A world whose plane has finished its launch and is flying at its starting place. Unless `arrivals` is true,
    /// nothing arrives, so a test can place exactly what it needs.
    static func flying(on field: PlaneGameField = phoneField, seed: UInt64 = 1, arrivals: Bool = false)
        -> PlaneGameWorld
    {
        var world = PlaneGameWorld(field: field, launchingFrom: CGPoint(x: -40, y: 400), after: 0, seed: seed)
        if !arrivals { world.spawner.close() }
        world.run(for: LoopPath.duration + frame)
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

    /// Puts a thing of `kind` this far ahead of the plane.
    mutating func addAhead(_ kind: PlaneGameThing.Kind, by offset: CGFloat = 0) {
        add(kind, at: CGPoint(x: plane.position.x + offset, y: plane.position.y))
    }
}
