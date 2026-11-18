import CoreGraphics
import Foundation

/// The morph from the game back into the Inbox, at one instant: what was in play fades, the plane flies up and round
/// into the envelopes' place and squeezes to a line, the envelopes open from it and spring back to size, the ring of doodles
/// flies home and the paper fades. Its last frame is the scene's rest pose exactly. With Reduce Motion on it is a
/// cross-fade.
nonisolated struct PlaneGameLanding: Equatable, Sendable {
    /// Seconds since the exit was asked for.
    let elapsed: TimeInterval
    let reduceMotion: Bool

    static let duration: TimeInterval = 1.9
    static let crossFade: TimeInterval = 0.3
    /// When the plane reaches the envelopes' place.
    static let planeArrives: TimeInterval = 0.75
    /// When the envelopes open from the line the plane squeezed to.
    static let pileOpens: TimeInterval = 0.87

    /// How long it takes.
    var length: TimeInterval { reduceMotion ? Self.crossFade : Self.duration }

    /// The opacity of what was in play, the HUD with it: obstacles, bad guys, shots and bursts.
    var play: Double {
        1 - PlaneGameEasing.ramp(elapsed, from: 0, to: Self.crossFade)
    }

    /// How far along its path to the envelopes' place the plane is.
    var planeProgress: Double {
        reduceMotion ? 0 : PlaneGameEasing.ramp(elapsed, from: 0, to: Self.planeArrives)
    }

    /// How much of the plane's width shows as it squeezes to a line.
    var planeWidth: CGFloat {
        reduceMotion
            ? 1 : 1 - PlaneGameEasing.easeIn(PlaneGameEasing.ramp(elapsed, from: Self.planeArrives, to: Self.pileOpens))
    }

    var planeOpacity: Double {
        reduceMotion ? play : (elapsed < Self.pileOpens ? 1 : 0)
    }

    /// How far the ring of doodles has flown from where the game left it to its place around the envelopes.
    var ringReturn: Double {
        reduceMotion ? 1 : PlaneGameEasing.smoothstep(PlaneGameEasing.ramp(elapsed, from: 0.10, to: 0.90))
    }

    /// The opacity of the ring's paper plane doodles, kept out of play: they fade back in over the second half of the
    /// ring's flight home, and are there in full at rest.
    var planeDoodle: Double {
        PlaneGameEasing.ramp(ringReturn, from: 0.5, to: 1)
    }

    /// The envelopes, or `nil` before they open from the line.
    var pile: PlaneGamePile? {
        if reduceMotion {
            return PlaneGamePile(fan: 1, lift: 0, scale: 1, width: 1, opacity: 1 - play)
        }
        guard elapsed >= Self.pileOpens else { return nil }
        guard elapsed < Self.duration else { return .rest }
        let opened = PlaneGameEasing.easeOut(PlaneGameEasing.ramp(elapsed, from: Self.pileOpens, to: 1.0))
        let grown = DoodleSpring.settle(elapsed - Self.pileOpens, response: 0.45, damping: 0.8)
        // The fan springs open as in the Inbox Zero entrance.
        let fanned = DoodleSpring.settle(elapsed - 0.95, response: 0.6, damping: 0.5)
        return PlaneGamePile(
            fan: settled(fanned), lift: 0,
            scale: PlaneGameTakeoff.foldedSize + (1 - PlaneGameTakeoff.foldedSize) * settled(grown), width: opened,
            opacity: 1)
    }

    /// The paper's opacity over the window.
    var paper: Double {
        reduceMotion ? play : 1 - PlaneGameEasing.smoothstep(PlaneGameEasing.ramp(elapsed, from: 0.90, to: 1.35))
    }

    /// The ring of doodles' opacity: flying home around the envelopes, or fading with the paper when the scene has
    /// no room for them.
    func backdrop(decorated: Bool) -> Double {
        decorated ? 1 : paper
    }

    /// A spring's value, with what is left of its swing taken out over the last moments, so the last frame is the
    /// rest pose exactly and not a hair from it.
    private func settled(_ spring: Double) -> Double {
        let still = PlaneGameEasing.smoothstep(PlaneGameEasing.ramp(elapsed, from: 1.5, to: Self.duration))
        return spring + (1 - spring) * still
    }
}

/// Leaving when the Inbox has mail again, so there is nothing to fold back into: the plane flies straight up off the
/// top edge and the paper fades, showing the list.
nonisolated struct PlaneGameFlyOff: Equatable, Sendable {
    /// Seconds since the exit was asked for.
    let elapsed: TimeInterval

    static let duration: TimeInterval = 0.4
    /// How fast the plane leaves, in points a second.
    static let speed: CGFloat = 900

    /// The paper's opacity, and everything on it.
    var paper: Double { 1 - PlaneGameEasing.ramp(elapsed, from: 0, to: Self.duration) }

    /// How far the plane has flown up.
    var planeRise: CGFloat { Self.speed * CGFloat(max(elapsed, 0)) }
}
