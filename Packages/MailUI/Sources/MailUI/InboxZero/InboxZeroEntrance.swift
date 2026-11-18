import CoreGraphics
import Foundation

/// The Inbox Zero scene coming on, at one instant. Earned, the envelopes rise and fan open, the doodles draw
/// themselves in from the envelopes outward, then the words follow; found, the whole scene fades in. Everything is a
/// function of the time since the Inbox emptied, so a frame is drawn by asking.
nonisolated struct InboxZeroEntrance: Equatable, Sendable {
    let arrival: InboxZeroArrival
    /// Seconds since the Inbox emptied, or `nil` while the scene holds still for Reduce Motion, which shows it in
    /// place.
    let elapsed: TimeInterval?

    /// When the envelopes appear, after the last row has gone.
    static let pileAppears: TimeInterval = 0.10
    /// When they start to fan open.
    static let fanOpens: TimeInterval = 0.18
    /// When the doodles start drawing themselves in.
    static let doodlesDraw: TimeInterval = 0.30
    /// When the doodles in the pane beside the list start drawing themselves in: as the ring's outer doodles do, so
    /// the drawing carries on across the line between them.
    static let beyondDraws: TimeInterval = doodlesDraw + 0.2
    /// When the drift starts easing in.
    static let driftStarts: TimeInterval = 0.35
    /// When the title comes in, and the line under it a moment later.
    static let titleAppears: TimeInterval = 0.45
    static let lineAppears: TimeInterval = 0.55
    /// When a paper plane takes off from the envelopes.
    static let planeLeaves: TimeInterval = 0.60
    /// A found scene fades in over this long.
    static let fadeTime: TimeInterval = 0.35

    /// The whole scene's opacity.
    var opacity: Double {
        guard arrival == .found, let elapsed else { return 1 }
        return min(max(elapsed / Self.fadeTime, 0), 1)
    }

    /// The envelopes' opacity.
    var pileOpacity: Double {
        guard arrival == .earned, let elapsed else { return 1 }
        return min(max((elapsed - Self.pileAppears) / 0.2, 0), 1)
    }

    /// How far below their place the envelopes are as they rise into it.
    var pileDrop: CGFloat {
        guard arrival == .earned, let elapsed else { return 0 }
        return 36 * (1 - rise(elapsed))
    }

    /// The envelopes' size, as a fraction of their own.
    var pileScale: CGFloat {
        guard let elapsed else { return 1 }
        switch arrival {
        case .earned: return 0.8 + 0.2 * rise(elapsed)
        case .found: return 0.94 + 0.06 * Self.easeOut(elapsed / Self.fadeTime)
        case .settled: return 1
        }
    }

    /// How far the envelopes have fanned open: 0 squared up, 1 as in the icon, swinging a little past it on the way.
    var fan: Double {
        guard arrival == .earned, let elapsed else { return 1 }
        return DoodleSpring.settle(elapsed - Self.fanOpens, response: 0.6, damping: 0.5)
    }

    /// The doodles drawing themselves in from `origin`, or `nil` when they are all there from the start.
    func reveal(from origin: CGPoint, reach: CGFloat) -> DoodleReveal? {
        guard arrival == .earned, let elapsed, elapsed < Self.doodlesDraw + DoodleReveal.total else { return nil }
        return DoodleReveal(origin: origin, reach: reach, elapsed: elapsed - Self.doodlesDraw)
    }

    /// The doodles in the pane beside the list drawing themselves in from `origin`, the envelopes in the pane's space,
    /// out to `reach`, its farthest corner; or `nil` when they are all there from the start.
    func revealBeyond(from origin: CGPoint, reach: CGFloat) -> DoodleReveal? {
        guard arrival == .earned, let elapsed, elapsed < Self.beyondDraws + DoodleReveal.total else { return nil }
        return DoodleReveal(origin: origin, reach: reach, elapsed: elapsed - Self.beyondDraws)
    }

    /// How far a line of text that comes in at `delay` has come: 0 hidden and 10 points low, 1 in place.
    func text(appearingAt delay: TimeInterval) -> Double {
        guard arrival == .earned, let elapsed else { return 1 }
        return Self.easeOut((elapsed - delay) / 0.4)
    }

    private func rise(_ elapsed: TimeInterval) -> Double {
        DoodleSpring.settle(elapsed - Self.pileAppears, response: 0.55, damping: 0.68)
    }

    private static func easeOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 - pow(1 - t, 3)
    }
}
