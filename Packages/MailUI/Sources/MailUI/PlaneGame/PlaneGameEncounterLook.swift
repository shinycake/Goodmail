import CoreGraphics
import Foundation
import PlaneGame

// What the screen draws of the power-ups and the bosses at one instant, worked out from the world as pure values, so
// they can be tested without drawing anything.

/// What the power-ups put on the plane, as drawn now.
nonisolated struct PlaneGameKit: Equatable, Sendable {
    /// Whether Bubble Wrap is around it.
    let isWrapped: Bool
    /// How much of the weapon's arc shows, from 0 to 1, or `nil` when none shows: with single shots, or in the
    /// blink's dark half.
    let arc: Double?

    /// The weapon's arc blinks this often in its last `blinksFor` seconds.
    static let blinksFor: TimeInterval = 2
    static let blinkEvery: TimeInterval = 0.25

    /// What `weapon` and Bubble Wrap put on the plane. The arc shortens as the weapon's time runs out and blinks for
    /// its last two seconds, or holds steady with Reduce Motion on.
    init(weapon: PlaneGameWeapon, isWrapped: Bool, reduceMotion: Bool) {
        self.isWrapped = isWrapped
        guard let remaining = weapon.remaining else {
            arc = nil
            return
        }
        let blinkedOff =
            !reduceMotion && remaining < Self.blinksFor
            && !Int(remaining / (Self.blinkEvery / 2)).isMultiple(of: 2)
        arc = blinkedOff ? nil : min(max(remaining / PlaneGameRules.weaponTime, 0), 1)
    }
}

/// A boss as drawn now: where, how strongly, whether it flashes, and, as it falls, its three bursts and its points.
nonisolated struct PlaneGameBossSprite: Equatable, Sendable {
    let kind: PlaneGameBoss.Kind
    let position: CGPoint
    let opacity: Double
    /// A shot struck it just now.
    let isFlashing: Bool
    /// The bursts it comes apart in, while they show.
    let bursts: [Burst]
    /// Its points rising from it as it falls, or `nil` before then.
    let points: Points?

    nonisolated struct Burst: Equatable, Sendable {
        let position: CGPoint
        /// How far through it is, from 0 to 1.
        let progress: Double
    }

    nonisolated struct Points: Equatable, Sendable {
        let value: Int
        let position: CGPoint
        let opacity: Double
    }

    /// When each of the three bursts starts, in seconds of the fall, and where around the boss's middle it is, in
    /// shares of its radius.
    static let burstTimes: [TimeInterval] = [0, 0.4, 0.8]
    static let burstPlaces = [CGPoint(x: -0.35, y: -0.2), CGPoint(x: 0.4, y: 0.15), CGPoint(x: 0, y: 0)]
    static let burstLength: TimeInterval = 0.4

    /// `boss` as drawn, `sinceStruck` seconds after a shot last struck it. It shakes as it falls, fading over the
    /// last third; with Reduce Motion on it holds still, doesn't flash, and its points don't rise.
    init(boss: PlaneGameBoss, sinceStruck: TimeInterval?, reduceMotion: Bool) {
        kind = boss.kind
        isFlashing = !reduceMotion && sinceStruck.map { $0 < PlaneGameBurst.flash } == true
        guard case .falling(let elapsed) = boss.status else {
            position = boss.position
            opacity = 1
            bursts = []
            points = nil
            return
        }
        let fall = PlaneGameRules.bossFall
        let calming = 1 - PlaneGameEasing.ramp(elapsed, from: 0, to: fall)
        let shake = reduceMotion ? 0 : 4 * CGFloat(sin(elapsed * 70) * calming)
        position = CGPoint(x: boss.position.x + shake, y: boss.position.y)
        opacity = 1 - PlaneGameEasing.ramp(elapsed, from: fall * 2 / 3, to: fall)
        bursts = zip(Self.burstTimes, Self.burstPlaces).compactMap { start, place in
            let progress = (elapsed - start) / Self.burstLength
            guard progress >= 0, progress < 1 else { return nil }
            return Burst(
                position: CGPoint(
                    x: boss.position.x + place.x * boss.radius, y: boss.position.y + place.y * boss.radius),
                progress: progress)
        }
        let rise = reduceMotion ? 0 : 36 * CGFloat(PlaneGameEasing.easeOut(elapsed / fall))
        points = Points(
            value: boss.points, position: CGPoint(x: boss.position.x, y: boss.position.y - rise),
            opacity: 1 - PlaneGameEasing.ramp(elapsed, from: fall * 0.75, to: fall))
    }
}

/// The boss's line of hits left under the score, as drawn now.
nonisolated struct PlaneGameBossLine: Equatable, Sendable {
    let kind: PlaneGameBoss.Kind
    let hitsLeft: Int
    /// How much of the track has drawn itself in, from 0 to 1.
    let drawn: Double
    /// The share of the track the hits left fill, from 0 to 1.
    let left: Double
    let opacity: Double

    /// The longest the line is.
    static let width: CGFloat = 160

    /// The line for `boss`: it draws itself in as the boss slides in, shortens with each hit, and fades as it
    /// falls. With Reduce Motion on it is simply there.
    init(boss: PlaneGameBoss, reduceMotion: Bool) {
        kind = boss.kind
        hitsLeft = boss.hitsLeft
        left = Double(boss.hitsLeft) / Double(max(boss.hits, 1))
        switch boss.status {
        case .arriving(let elapsed):
            drawn = reduceMotion ? 1 : PlaneGameEasing.smoothstep(elapsed / PlaneGameRules.bossArrival)
            opacity = 1
        case .fighting:
            drawn = 1
            opacity = 1
        case .falling(let elapsed):
            drawn = 1
            opacity = 1 - PlaneGameEasing.ramp(elapsed, from: 0, to: PlaneGameRules.bossFall / 2)
        }
    }
}
