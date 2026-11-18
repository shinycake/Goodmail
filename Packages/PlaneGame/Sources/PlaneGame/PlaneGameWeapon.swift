public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What the plane fires.
public enum PlaneGameWeapon: Equatable, Sendable {
    case single
    /// Reply All: three shots at once, one straight up and one leaning to each side, for `remaining` seconds.
    case spread(remaining: TimeInterval)
    /// Express: twice as fast, for `remaining` seconds.
    case rapid(remaining: TimeInterval)

    /// Seconds left before it goes back to single shots, or `nil` for single shots.
    public var remaining: TimeInterval? {
        switch self {
        case .single: nil
        case .spread(let remaining), .rapid(let remaining): remaining
        }
    }

    /// The same weapon `dt` seconds later: single shots again once its time is up.
    func aged(by dt: TimeInterval) -> PlaneGameWeapon {
        switch self {
        case .single: .single
        case .spread(let remaining): remaining > dt ? .spread(remaining: remaining - dt) : .single
        case .rapid(let remaining): remaining > dt ? .rapid(remaining: remaining - dt) : .single
        }
    }

    /// The time between shots.
    var fireEvery: TimeInterval {
        switch self {
        case .single, .spread: PlaneGameRules.fireEvery
        case .rapid: PlaneGameRules.rapidFireEvery
        }
    }

    /// The sideways speed of each shot it fires at once, in points a second.
    var drifts: [CGFloat] {
        switch self {
        case .single, .rapid:
            return [0]
        case .spread:
            let lean = PlaneGameRules.shotSpeed * CGFloat(tan(PlaneGameRules.spreadAngle * .pi / 180))
            return [-lean, 0, lean]
        }
    }
}
