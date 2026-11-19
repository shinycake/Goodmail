public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The game with nothing to draw it: the plane, what comes at it, the shots and the score, stepped on by
/// `advance(by:input:)`. Equal seeds and equal inputs give equal worlds.
public struct PlaneGameWorld: Equatable, Sendable {
    public private(set) var field: PlaneGameField
    public internal(set) var plane: PlaneGamePlane
    public internal(set) var things: [PlaneGameThing] = []
    public internal(set) var shots: [PlaneGameShot] = []
    public internal(set) var bursts: [PlaneGameBurst] = []
    public internal(set) var score = 0
    public internal(set) var lives = PlaneGameRules.lives
    /// Seconds played.
    public internal(set) var elapsed: TimeInterval = 0
    /// Points the world has scrolled, which the backdrop is drawn from.
    public internal(set) var distance: CGFloat = 0
    /// What the plane fires.
    public internal(set) var weapon = PlaneGameWeapon.single
    /// Bubble Wrap is around the plane, and the next hit costs no life.
    public internal(set) var isShielded = false

    /// When the plane sets off, in seconds played. The scroll eases in from then.
    let setOff: TimeInterval
    var generator: SeededGenerator
    var spawner = PlaneGameSpawner()
    var encounter = Encounter.waves(played: 0, next: 1)
    var trigger = Trigger.ready
    /// Seconds since the plane's trail last took a sample.
    var sinceTrailSample: TimeInterval = 0
    var nextID = 0

    /// The plane's gun: it fires as soon as the finger is down, then cools for `PlaneGameRules.fireEvery`.
    enum Trigger: Equatable, Sendable {
        case ready
        case cooling(sinceShot: TimeInterval)
    }

    /// A new game. The plane waits `delay` seconds where `launch` starts it, then flies onto the field to its
    /// starting place.
    public init(field: PlaneGameField, launch: PlaneGameLaunch, after delay: TimeInterval, seed: UInt64) {
        self.field = field
        setOff = max(delay, 0)
        generator = SeededGenerator(seed: seed)
        let path = launch.path(onto: field)
        plane = PlaneGamePlane(
            position: path.start, heading: path.heading(at: 0), trail: [],
            status: .launching(path, elapsed: -setOff))
    }

    /// Points a second the world is falling now, on the screen: faster over the first two minutes, and faster again
    /// each round.
    public var speed: CGFloat {
        guard elapsed > setOff else { return 0 }
        let hardening = min(elapsed / PlaneGameRules.hardeningTime, 1)
        let cruising =
            PlaneGameRules.cruisingSpeed + (PlaneGameRules.topSpeed - PlaneGameRules.cruisingSpeed) * hardening
        return cruising * heat.scroll * field.pace
            * FlightPath.smoothstep((elapsed - setOff) / PlaneGameRules.rampTime)
    }

    /// The round being played: the number of the boss that ends it.
    public var round: Int {
        encounter.round
    }

    /// How hard this round plays.
    var heat: PlaneGameHeat {
        PlaneGameHeat(round: round)
    }

    /// The plane has fallen off the field.
    public var isOver: Bool {
        if case .down(let elapsed) = plane.status { elapsed >= PlaneGameRules.fallTime } else { false }
    }

    /// Moves everything on by `dt` seconds and says what happened.
    ///
    /// A long step is taken in short ones, so nothing fast passes through something without touching it. The slide
    /// is shared out between them. A step longer than `PlaneGameRules.longestAdvance` counts as that long.
    @discardableResult
    public mutating func advance(by dt: TimeInterval, input: PlaneGameInput) -> [PlaneGameEvent] {
        guard dt.isFinite, dt > 0 else { return [] }
        let dt = min(dt, PlaneGameRules.longestAdvance)
        let slide = input.slide.isFinite ? input.slide : 0
        let count = (dt / PlaneGameRules.longestStep).rounded(.up)
        let share = PlaneGameInput(slide: slide / count, isFiring: input.isFiring)
        var events: [PlaneGameEvent] = []
        for _ in 0..<Int(count) {
            events += step(by: dt / count, input: share)
        }
        return events
    }

    /// The field changed size, as on rotation. The plane moves to the new row inside the new lanes, or a launching
    /// one heads for its new starting place, everything in play is brought inside the lanes, and a boss keeps inside
    /// them and under the new ceiling. Nothing else moves.
    public mutating func resize(to field: PlaneGameField) {
        self.field = field
        switch plane.status {
        case .launching(let path, let elapsed):
            plane.status = .launching(path.ending(at: field.startingPlace), elapsed: elapsed)
        case .flying, .shaken:
            plane.position = field.placingPlane(atX: plane.position.x)
        case .down:
            break
        }
        for index in things.indices {
            let kind = things[index].kind
            things[index].lane = field.lanes(inset: kind.radius + kind.swing).clamping(things[index].lane)
            things[index].position.x = field.lanes.clamping(things[index].position.x)
        }
        if case .boss(var boss) = encounter {
            boss.place(on: field)
            encounter = .boss(boss)
        }
    }

    /// Puts a thing of `kind` at `position`, sliding sideways at `drift`, unless the field already holds all it can.
    /// Arrivals, what a boss sends and the replies Out of Office sends back come through here.
    mutating func send(_ kind: PlaneGameThing.Kind, at position: CGPoint, drift: CGFloat = 0) {
        guard things.count < PlaneGameRules.fieldHolds else { return }
        add(kind, at: position, drift: drift)
    }

    /// Puts a thing of `kind` at `position`, sliding sideways at `drift`, however full the field is. A beaten boss's
    /// drops come through here, and tests place things with it.
    mutating func add(_ kind: PlaneGameThing.Kind, at position: CGPoint, drift: CGFloat = 0) {
        things.append(PlaneGameThing(id: takeID(), kind: kind, position: position, drift: drift))
    }

    mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

extension PlaneGameField {
    /// Where the plane flies with its middle at `x`: on the row, kept inside the lanes by its radius.
    func placingPlane(atX x: CGFloat) -> CGPoint {
        CGPoint(x: lanes(inset: PlaneGameRules.planeRadius).clamping(x), y: row)
    }
}

extension ClosedRange<CGFloat> {
    func clamping(_ value: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
