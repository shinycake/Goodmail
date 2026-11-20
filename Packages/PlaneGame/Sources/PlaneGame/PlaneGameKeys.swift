public import Foundation

// CGFloat comes with Foundation, and with CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The keyboard's side of the game's input: the arrows steer and Space fires, for as long as they are held. It turns
/// the keys held since the last step into the same `PlaneGameInput` a finger makes, so the two work together.
public struct PlaneGameKeys: Equatable, Sendable {
    public enum Key: Hashable, Sendable {
        case left
        case right
        case fire
    }

    /// How the plane is being steered by the keys: not at all, or one way for this long, which eases it in.
    private enum Steering: Equatable {
        case straight
        case going(Direction, for: TimeInterval)
    }

    private enum Direction {
        case left
        case right

        var sign: CGFloat { self == .left ? -1 : 1 }
    }

    /// How far the plane slides a second at full speed, in widths of the lanes: across them in a little under a
    /// second, about as fast as a deliberate swipe.
    public static let lanesPerSecond: CGFloat = 1.2
    /// How long a key takes to bring the plane up to full speed, so a tap nudges it and a hold glides.
    public static let easeIn: TimeInterval = 0.12

    /// The keys down now.
    private var held: Set<Key> = []
    /// The keys that went down since the last step, which count for that step even if they are up again, so a tap
    /// quicker than a frame still steers and fires.
    private var pressed: Set<Key> = []
    private var steering = Steering.straight

    public init() {}

    public mutating func press(_ key: Key) {
        held.insert(key)
        pressed.insert(key)
    }

    public mutating func release(_ key: Key) {
        held.remove(key)
    }

    /// Lets go of everything, as when the game pauses or the window stops having the keyboard, so a key released
    /// somewhere else never stays down.
    public mutating func releaseAll() {
        self = PlaneGameKeys()
    }

    /// What the keys did over a step of `dt` seconds in lanes `fieldWidth` across: how far they slid the plane, and
    /// whether Space is down. Both arrows down steer nowhere.
    public mutating func advance(by dt: TimeInterval, fieldWidth: CGFloat) -> PlaneGameInput {
        let active = held.union(pressed)
        pressed = []
        let direction: Direction? =
            switch (active.contains(.left), active.contains(.right)) {
            case (true, false): .left
            case (false, true): .right
            case (true, true), (false, false): nil
            }
        switch (direction, steering) {
        case (nil, _):
            steering = .straight
        case (let direction?, .going(direction, let age)):
            steering = .going(direction, for: age + dt)
        case (let direction?, _):
            steering = .going(direction, for: dt)
        }
        let isFiring = active.contains(.fire)
        guard case .going(let direction, let age) = steering, dt > 0, fieldWidth.isFinite, fieldWidth > 0 else {
            return PlaneGameInput(isFiring: isFiring)
        }
        let speed = fieldWidth * Self.lanesPerSecond * min(CGFloat(age / Self.easeIn), 1)
        return PlaneGameInput(slide: direction.sign * speed * CGFloat(dt), isFiring: isFiring)
    }
}
