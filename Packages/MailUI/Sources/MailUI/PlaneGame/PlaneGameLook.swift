import CoreGraphics
import Foundation
import PlaneGame

/// Everything the game screen draws at one instant, worked out from the phase and the game clock in one place, so
/// the view only draws it.
nonisolated struct PlaneGameLook: Equatable, Sendable {
    /// The paper's opacity over the window.
    let paper: Double
    /// The HUD's opacity.
    let hud: Double
    /// The envelopes, while the plane folds out of them or back into them.
    let pile: Pile?
    /// The paper planes that were in the air at the tenth tap, carrying on as the paper comes up.
    let flights: Flights?
    let canvas: PlaneGameFrame

    /// The envelopes in a pose, centered on the screen at `center`.
    nonisolated struct Pile: Equatable, Sendable {
        let pose: PlaneGamePile
        let center: CGPoint
        let width: CGFloat
    }

    /// The scene's paper planes on the scene's field, fading with the paper over them.
    nonisolated struct Flights: Equatable, Sendable {
        let scene: DoodleScene
        let opacity: Double
    }
}

/// What the canvas draws: the backdrop, what is in play and the plane.
nonisolated struct PlaneGameFrame: Equatable, Sendable {
    /// The ring of doodles, on the screen, one for each of `Doodle.inboxZero`.
    let backdrop: [Placed]
    /// Obstacles, bad guys, pickups, shots and bursts.
    let world: PlaneGameWorld
    /// Their opacity.
    let play: Double
    let plane: PlaneGameSprite?
    /// Whether the ring is drawn the way the Inbox Zero scene draws it for a right-to-left language, so it is the
    /// ring the game takes over and folds back into. Nothing in play is mirrored.
    let ringRightToLeft: Bool
    let reduceMotion: Bool

    /// A doodle of the ring where it is drawn, and how strongly.
    nonisolated struct Placed: Equatable, Sendable {
        let pose: DoodlePose
        let opacity: Double
    }
}

/// The reader's plane as drawn.
nonisolated struct PlaneGameSprite: Equatable, Sendable {
    let position: CGPoint
    /// Radians clockwise from pointing up.
    let heading: Double
    /// Where it has just been, nearest first.
    let trail: [CGPoint]
    /// How much of its width shows as it opens from a line or squeezes to one.
    let width: CGFloat
    let opacity: Double
}

extension PlaneGameModel {
    /// What the screen draws now.
    var look: PlaneGameLook {
        switch phase {
        case .flying(.takeoff):
            let takeoff = takeoff
            return PlaneGameLook(
                paper: takeoff.paper, hud: takeoff.hud,
                pile: takeoff.pile(from: handoff.scene).map {
                    .init(pose: $0, center: handoff.stage.center, width: handoff.stage.pileWidth)
                },
                flights: flightsInTheAir(fading: 1 - takeoff.paper),
                canvas: frame(
                    backdrop: ring(
                        backdrop.poses(at: distance), opacity: takeoff.backdrop(decorated: handoff.stage.isDecorated),
                        planes: takeoff.planeDoodle),
                    play: 1,
                    plane: sprite(
                        width: takeoff.planeWidth, opacity: takeoff.planeOpacity, turning: takeoff.planeTurn)))
        case .flying(.again), .over:
            return PlaneGameLook(
                paper: 1, hud: 1, pile: nil, flights: nil,
                canvas: frame(
                    backdrop: ring(backdrop.poses(at: distance), opacity: 1, planes: 0), play: 1,
                    plane: sprite(width: 1, opacity: 1)))
        case .leaving(let leaving):
            return look(leaving: leaving, elapsed: clock - leaving.since)
        case .gone:
            // The scene underneath draws the envelopes and the ring again from this frame on.
            return PlaneGameLook(
                paper: 0, hud: 0, pile: nil, flights: nil,
                canvas: frame(backdrop: [], play: 0, plane: nil))
        }
    }

    private func look(leaving: PlaneGameLeaving, elapsed: TimeInterval) -> PlaneGameLook {
        switch leaving.way {
        case .home(let stage, let path):
            let landing = PlaneGameLanding(elapsed: elapsed, reduceMotion: reduceMotion)
            let ring =
                stage.isDecorated
                ? backdrop.poses(
                    at: distance, returning: landing.ringReturn,
                    to: PlaneGameBackdrop.rest(of: Doodle.inboxZero, on: stage, rightToLeft: handoff.scene.rightToLeft))
                : backdrop.poses(at: distance)
            let progress = landing.planeProgress
            let plane = PlaneGameSprite(
                position: path.point(at: progress), heading: path.heading(at: progress),
                trail: (1...PlaneFlight.trailSteps).map { path.point(at: progress - Double($0) * 0.02) },
                width: landing.planeWidth, opacity: landing.planeOpacity)
            return PlaneGameLook(
                paper: landing.paper, hud: landing.play,
                pile: landing.pile.map { .init(pose: $0, center: stage.center, width: stage.pileWidth) },
                flights: nil,
                canvas: frame(
                    backdrop: self.ring(
                        ring, opacity: landing.backdrop(decorated: stage.isDecorated), planes: landing.planeDoodle),
                    play: landing.play, plane: plane))
        case .away:
            let flyOff = PlaneGameFlyOff(elapsed: elapsed)
            let plane = sprite(width: 1, opacity: 1).map {
                PlaneGameSprite(
                    position: CGPoint(x: $0.position.x, y: $0.position.y - flyOff.planeRise), heading: $0.heading,
                    trail: $0.trail, width: 1, opacity: 1)
            }
            return PlaneGameLook(
                paper: flyOff.paper, hud: flyOff.paper, pile: nil, flights: nil,
                canvas: frame(
                    backdrop: ring(backdrop.poses(at: distance), opacity: flyOff.paper, planes: 0),
                    play: flyOff.paper, plane: plane))
        }
    }

    private func frame(backdrop: [PlaneGameFrame.Placed], play: Double, plane: PlaneGameSprite?) -> PlaneGameFrame {
        PlaneGameFrame(
            backdrop: backdrop, world: world, play: play, plane: plane, ringRightToLeft: handoff.scene.rightToLeft,
            reduceMotion: reduceMotion)
    }

    /// The ring at `poses`, at `opacity`, with its paper plane doodles at `planes` of that: in play they would read
    /// as a second plane, so they leave with the paper and come home with the ring.
    private func ring(_ poses: [DoodlePose], opacity: Double, planes: Double) -> [PlaneGameFrame.Placed] {
        zip(Doodle.inboxZero, poses).map { doodle, pose in
            PlaneGameFrame.Placed(pose: pose, opacity: doodle.shape == .plane ? opacity * planes : opacity)
        }
    }

    /// The world's plane, or `nil` once it has fallen off the field. It points `turning` of the way from straight up
    /// to its own heading.
    private func sprite(width: CGFloat, opacity: Double, turning: Double = 1) -> PlaneGameSprite? {
        let plane = world.plane
        let blink: Double
        switch plane.status {
        case .launching, .flying:
            blink = 1
        case .shaken(let remaining):
            // It blinks while it can't be hit; with Reduce Motion on it holds at half strength instead.
            blink = reduceMotion ? 0.5 : (Int(remaining / 0.1).isMultiple(of: 2) ? 1 : 0.2)
        case .down:
            if world.isOver { return nil }
            blink = 1
        }
        return PlaneGameSprite(
            position: plane.position, heading: plane.heading * turning, trail: plane.trail, width: width,
            opacity: opacity * blink)
    }

    /// The scene's paper planes carrying on from the tenth tap, on the scene's clock, with no new one setting off,
    /// at `fading`. They keep their courses but go with the paper, so only the envelopes and the ring are left once
    /// it is up.
    private func flightsInTheAir(fading: Double) -> PlaneGameLook.Flights? {
        let scene = handoff.scene
        guard handoff.stage.isDecorated, fading > 0, case .running(let tapped) = scene.clock else { return nil }
        return PlaneGameLook.Flights(
            scene: DoodleScene(
                size: scene.size, pokes: scene.pokes, clock: .running(tapped + clock), rightToLeft: scene.rightToLeft,
                focus: scene.focus, energy: scene.energy, passInterval: scene.passInterval, quietFrom: tapped),
            opacity: fading)
    }
}
