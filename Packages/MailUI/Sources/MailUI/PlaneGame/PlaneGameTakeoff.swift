import CoreGraphics
import Foundation

/// The envelopes' pose while the game draws them, folding into the plane or out of it.
nonisolated struct PlaneGamePile: Equatable, Sendable {
    /// How wide they are fanned: 1 as in the icon, 0 squared up.
    let fan: Double
    /// How far they have risen from their place.
    let lift: CGFloat
    /// Their size, as a fraction of their own.
    let scale: CGFloat
    /// How much of their width shows: 1 as drawn, 0 squeezed to an upright line.
    let width: CGFloat
    let opacity: Double

    /// The scene's rest pose, which the landing ends on.
    static let rest = PlaneGamePile(fan: 1, lift: 0, scale: 1, width: 1, opacity: 1)
}

/// The morph from the Inbox into the game, at one instant: the envelopes square up, shrink and squeeze to a line,
/// the paper comes over the window, the plane opens from the line and the HUD fades in. Everything is a function of
/// the time since the tenth tap, so a frame is drawn by asking. With Reduce Motion on it is a cross-fade.
nonisolated struct PlaneGameTakeoff: Equatable, Sendable {
    /// Seconds since the tenth tap.
    let elapsed: TimeInterval
    let reduceMotion: Bool

    /// When the plane sets off on its loop, from the line the envelopes squeezed to.
    static let planeSetsOff: TimeInterval = 0.42
    /// How long the morph takes, and how long the cross-fade takes with Reduce Motion on.
    static let duration: TimeInterval = 1.3
    static let crossFade: TimeInterval = 0.3

    /// Whether it has played out, and the reader is simply playing.
    var isDone: Bool { elapsed >= (reduceMotion ? Self.crossFade : Self.duration) }

    /// The paper's opacity over the window.
    var paper: Double {
        reduceMotion
            ? PlaneGameEasing.ramp(elapsed, from: 0, to: Self.crossFade)
            : PlaneGameEasing.smoothstep(PlaneGameEasing.ramp(elapsed, from: 0.05, to: 0.40))
    }

    /// The envelopes, posed `from` where the scene's frame left them, or `nil` once they have become the plane.
    func pile(from scene: DoodleScene) -> PlaneGamePile? {
        if reduceMotion {
            guard elapsed < Self.crossFade else { return nil }
            return PlaneGamePile(
                fan: scene.fan, lift: scene.lift, scale: 1, width: 1, opacity: 1 - elapsed / Self.crossFade)
        }
        guard elapsed < Self.planeSetsOff else { return nil }
        let squared = PlaneGameEasing.easeOut(PlaneGameEasing.ramp(elapsed, from: 0, to: 0.25))
        let shrunk = PlaneGameEasing.smoothstep(PlaneGameEasing.ramp(elapsed, from: 0.10, to: 0.40))
        let squeezed = PlaneGameEasing.easeIn(PlaneGameEasing.ramp(elapsed, from: 0.30, to: Self.planeSetsOff))
        return PlaneGamePile(
            fan: scene.fan * (1 - squared), lift: scene.lift * (1 - squared), scale: 1 - (1 - Self.foldedSize) * shrunk,
            width: 1 - squeezed, opacity: 1)
    }

    /// How much of the plane's width shows as it opens from the line, overshooting a little.
    var planeWidth: CGFloat {
        reduceMotion ? 1 : PlaneGameEasing.backOut(PlaneGameEasing.ramp(elapsed, from: Self.planeSetsOff, to: 0.60))
    }

    /// The plane's opacity: there from the fold on, or fading in with Reduce Motion.
    var planeOpacity: Double {
        reduceMotion ? paper : 1
    }

    /// The HUD's opacity.
    var hud: Double {
        reduceMotion ? paper : PlaneGameEasing.smoothstep(PlaneGameEasing.ramp(elapsed, from: 0.9, to: 1.3))
    }

    /// The opacity of the ring's paper plane doodles, which would read as a second plane in play: they go with the
    /// paper.
    var planeDoodle: Double {
        1 - paper
    }

    /// The ring of doodles' opacity: there all along around the envelopes, or fading in with the paper when the scene
    /// had no room for them.
    func backdrop(decorated: Bool) -> Double {
        decorated ? 1 : paper
    }

    /// The envelopes' size when they squeeze into the plane, and when they open out of it.
    static let foldedSize: CGFloat = 0.24
}

/// The curves the morphs are drawn with, over a value that runs from 0 to 1.
nonisolated enum PlaneGameEasing {
    /// How far `value` is from `start` to `end`, from 0 to 1.
    static func ramp(_ value: Double, from start: Double, to end: Double) -> Double {
        min(max((value - start) / (end - start), 0), 1)
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func easeOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    static func easeIn(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * t
    }

    /// Eases out past 1 and settles back on it.
    static func backOut(_ x: Double) -> Double {
        // Exact at both ends: the curve's own arithmetic leaves a hair below 0 at the start.
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        let t = x - 1
        let overshoot = 1.7
        return 1 + t * t * ((overshoot + 1) * t + overshoot)
    }
}
