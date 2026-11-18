import CoreGraphics
import Foundation

/// Turns flight coordinates, where x grows toward the trailing edge, into the screen's, and back: the same flip both
/// ways, so a right-to-left layout reads a drag and draws a frame through it.
nonisolated struct PlaneGameMirror: Equatable, Sendable {
    let width: CGFloat
    let rightToLeft: Bool

    func flipped(_ point: CGPoint) -> CGPoint {
        rightToLeft ? CGPoint(x: width - point.x, y: point.y) : point
    }
}

/// The Inbox Zero ring of doodles behind the game. Each drifts toward the leading edge at its own share of the world's
/// speed, and once past it comes round again from the trailing edge at a new height. Where each is follows from how far
/// the world has scrolled, so a frame is drawn by asking. At distance 0 it is the ring as the scene last drew it, until
/// the screen changes size.
nonisolated struct PlaneGameBackdrop: Equatable, Sendable {
    /// Where each doodle is on the screen at `origin`.
    private(set) var seeds: [DoodlePose]
    /// The distance the drift is measured from: 0, or where the screen last changed size.
    private(set) var origin: CGFloat = 0
    /// The angle each doodle rests at, which it comes round again at.
    let angles: [Double]
    /// The screen's width, flipped through for a right-to-left layout.
    private(set) var mirror: PlaneGameMirror
    /// The heights a doodle coming round again keeps between.
    private(set) var band: ClosedRange<CGFloat>
    /// With Reduce Motion on, the ring holds still.
    let reduceMotion: Bool

    /// A doodle goes this far past an edge before it wraps, so it is never seen to jump.
    static let margin: CGFloat = 50

    /// The ring of `doodles` as `handoff` drew it, on a screen `screen` in size. A scene without room for the ring
    /// hands over none, so the doodles start at their places around the middle of the screen instead.
    init(
        doodles: [Doodle], handoff: InboxZeroHandoff, screen: CGSize, band: ClosedRange<CGFloat>, reduceMotion: Bool
    ) {
        let rightToLeft = handoff.scene.rightToLeft
        if handoff.stage.isDecorated {
            let origin = handoff.stage.field.origin
            seeds = doodles.enumerated().map { index, doodle in
                let pose = handoff.scene.pose(of: doodle, at: index)
                return DoodlePose(
                    position: CGPoint(x: origin.x + pose.position.x, y: origin.y + pose.position.y), angle: pose.angle)
            }
        } else {
            let resting = DoodleScene(size: screen, pokes: [], clock: .stopped, rightToLeft: rightToLeft)
            seeds = doodles.enumerated().map { resting.pose(of: $1, at: $0) }
        }
        angles = doodles.map(\.angle)
        mirror = PlaneGameMirror(width: screen.width, rightToLeft: rightToLeft)
        self.band = band
        self.reduceMotion = reduceMotion
    }

    /// The screen changed size, as on rotation, once the world had scrolled `distance` points. Each doodle stays where it
    /// is, measured from the leading edge, drifts on from there, and comes round within the new width and band.
    mutating func fit(mirror: PlaneGameMirror, band: ClosedRange<CGFloat>, at distance: CGFloat) {
        let old = self.mirror
        seeds = poses(at: distance).map {
            DoodlePose(position: mirror.flipped(old.flipped($0.position)), angle: $0.angle)
        }
        origin = distance
        self.mirror = mirror
        self.band = band
    }

    /// How much of the world's speed the doodle at `index` drifts at: from 0.35, the farthest, to 0.6.
    static func depth(of index: Int) -> CGFloat {
        0.35 + 0.25 * CGFloat((index * 5) % 12) / 11
    }

    /// Where every doodle is once the world has scrolled `distance` points.
    func poses(at distance: CGFloat) -> [DoodlePose] {
        seeds.indices.map { pose(of: $0, at: distance) }
    }

    /// Where every doodle is `progress` of the way home from where `distance` left it to `rest`, its place in the ring,
    /// turning to its resting angle on the way.
    func poses(at distance: CGFloat, returning progress: Double, to rest: [DoodlePose]) -> [DoodlePose] {
        // Weighted from both ends, so progress 0 and 1 land exactly on where it was and where it rests.
        zip(poses(at: distance), rest).map { from, to in
            let t = CGFloat(progress)
            return DoodlePose(
                position: CGPoint(
                    x: from.position.x * (1 - t) + to.position.x * t, y: from.position.y * (1 - t) + to.position.y * t),
                angle: from.angle * (1 - progress) + to.angle * progress)
        }
    }

    /// Where each doodle rests in the ring around the envelopes of `stage`, on the screen: the poses the scene draws
    /// at rest, which the landing ends on.
    static func rest(of doodles: [Doodle], on stage: InboxZeroStage, rightToLeft: Bool) -> [DoodlePose] {
        let scene = DoodleScene(
            size: stage.field.size, pokes: [], clock: .stopped, rightToLeft: rightToLeft, focus: stage.focus)
        let origin = stage.field.origin
        return doodles.enumerated().map { index, doodle in
            let pose = scene.pose(of: doodle, at: index)
            return DoodlePose(
                position: CGPoint(x: origin.x + pose.position.x, y: origin.y + pose.position.y), angle: pose.angle)
        }
    }

    private func pose(of index: Int, at distance: CGFloat) -> DoodlePose {
        let seed = seeds[index]
        guard !reduceMotion else { return seed }
        let drift = Self.depth(of: index) * (distance - origin)
        // Where it is in flight coordinates, before any wrap.
        let along = mirror.flipped(seed.position).x - drift
        guard along < -Self.margin else {
            // Moved on the screen directly, so at `origin` it is exactly at its seed.
            let x = seed.position.x + (mirror.rightToLeft ? drift : -drift)
            return DoodlePose(position: CGPoint(x: x, y: seed.position.y), angle: seed.angle)
        }
        let span = mirror.width + 2 * Self.margin
        let laps = Int(((-Self.margin - along) / span).rounded(.up))
        let height = band.lowerBound + (band.upperBound - band.lowerBound) * Self.scatter(index, laps)
        return DoodlePose(
            position: mirror.flipped(CGPoint(x: along + CGFloat(laps) * span, y: height)), angle: angles[index])
    }

    /// A fraction from 0 to 1 that looks random but is the same for the same doodle and lap.
    private static func scatter(_ index: Int, _ laps: Int) -> CGFloat {
        var z = UInt64(truncatingIfNeeded: index &* 7919 &+ laps &* 104_729) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}
