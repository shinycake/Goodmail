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

    /// When the plane sets off, in seconds played. The scroll eases in from then.
    let setOff: TimeInterval
    var generator: SeededGenerator
    var spawner = PlaneGameSpawner()
    var trigger = Trigger.ready
    /// Seconds since the plane's trail last took a sample.
    var sinceTrailSample: TimeInterval = 0
    var nextID = 0

    /// The plane's gun: it fires as soon as the finger is down, then cools for `PlaneGameRules.fireEvery`.
    enum Trigger: Equatable, Sendable {
        case ready
        case cooling(sinceShot: TimeInterval)
    }

    /// A new game. The plane waits `delay` seconds at `launch`, then flies its loop to the starting place.
    public init(field: PlaneGameField, launchingFrom launch: CGPoint, after delay: TimeInterval, seed: UInt64) {
        self.field = field
        setOff = max(delay, 0)
        generator = SeededGenerator(seed: seed)
        plane = PlaneGamePlane(
            position: launch, heading: 0, trail: [],
            status: .launching(LoopPath(from: launch, to: field.startingPlace), elapsed: -setOff))
    }

    /// Points a second the world is scrolling now.
    public var speed: CGFloat {
        guard elapsed > setOff else { return 0 }
        let hardening = min(elapsed / PlaneGameRules.hardeningTime, 1)
        let cruising =
            PlaneGameRules.cruisingSpeed + (PlaneGameRules.topSpeed - PlaneGameRules.cruisingSpeed) * hardening
        return cruising * LoopPath.smoothstep((elapsed - setOff) / PlaneGameRules.rampTime)
    }

    /// The plane has fallen off the field.
    public var isOver: Bool {
        if case .down(let elapsed) = plane.status { elapsed >= PlaneGameRules.fallTime } else { false }
    }

    /// Moves everything on by `dt` seconds and says what happened.
    ///
    /// A long step is taken in short ones, so nothing fast passes through something without touching it. The drag
    /// is shared out between them. A step longer than `PlaneGameRules.longestAdvance` counts as that long.
    @discardableResult
    public mutating func advance(by dt: TimeInterval, input: PlaneGameInput) -> [PlaneGameEvent] {
        guard dt.isFinite, dt > 0 else { return [] }
        let dt = min(dt, PlaneGameRules.longestAdvance)
        let drag =
            input.drag.width.isFinite && input.drag.height.isFinite ? input.drag : CGSize(width: 0, height: 0)
        let count = (dt / PlaneGameRules.longestStep).rounded(.up)
        let share = PlaneGameInput(
            drag: CGSize(width: drag.width / count, height: drag.height / count), isFiring: input.isFiring)
        var events: [PlaneGameEvent] = []
        for _ in 0..<Int(count) {
            events += step(by: dt / count, input: share)
        }
        return events
    }

    /// The field changed size, as on rotation: everything keeps inside it.
    public mutating func resize(to field: PlaneGameField) {
        self.field = field
        switch plane.status {
        case .launching(let path, let elapsed):
            plane.status = .launching(LoopPath(from: path.start, to: field.startingPlace), elapsed: elapsed)
        case .flying, .shaken:
            plane.position = field.keepingPlane(plane.position)
        case .down:
            break
        }
        for index in things.indices {
            things[index].lane = field.band.clamping(things[index].lane)
            things[index].position.y = field.band.clamping(things[index].position.y)
        }
    }

    /// Puts a thing of `kind` at `position`. Arrivals come through here, and tests place things with it.
    mutating func add(_ kind: PlaneGameThing.Kind, at position: CGPoint) {
        things.append(PlaneGameThing(id: takeID(), kind: kind, position: position))
    }

    mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

extension PlaneGameField {
    /// `point` moved the least it takes to be where the plane may fly.
    func keepingPlane(_ point: CGPoint) -> CGPoint {
        let reach = max(size.width * PlaneGameRules.planeReach, PlaneGameRules.planeRadius)
        return CGPoint(x: min(max(point.x, PlaneGameRules.planeRadius), reach), y: band.clamping(point.y))
    }

    /// Where the plane's launch loop ends.
    var startingPlace: CGPoint {
        CGPoint(
            x: size.width * PlaneGameRules.startAt.x,
            y: band.clamping(size.height * PlaneGameRules.startAt.y))
    }
}

extension ClosedRange<CGFloat> {
    func clamping(_ value: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
