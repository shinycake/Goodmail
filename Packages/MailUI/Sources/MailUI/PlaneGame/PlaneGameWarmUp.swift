import PlaneGame
import SwiftUI

/// The paper plane game drawn once, out of sight, while the Inbox Zero scene sits still.
///
/// The first time SwiftUI meets a view type it reflects over it and asks the Swift runtime about its conformances, and
/// the runtime answers the first question about a type by reading every conformance in the app. For the game's views
/// that took 116 to 143 ms of the first game's first frame on an iPhone 17 Pro simulator, seven frames dropped as the
/// envelopes fold. A second game in the same launch had none of it. Drawing the game, its cards included, once the
/// scene has come to rest moves that cost to a moment when nothing on screen is moving.
enum PlaneGameWarmUp {
    /// Draws the game unless this launch has drawn it already.
    static func run() {
        _ = drawn
    }

    /// Initialized on first use and never again, so the game is drawn at most once a launch.
    private static let drawn: Void = draw()

    private static func draw() {
        let screen = CGSize(width: 402, height: 874)
        let stage = InboxZeroStage(field: CGRect(x: 0, y: 140, width: 402, height: 520), layout: .full, pileWidth: 200)
        let model = PlaneGameModel(
            handoff: InboxZeroHandoff(
                scene: DoodleScene(size: stage.field.size, pokes: [], clock: .stopped, rightToLeft: false),
                stage: stage),
            screen: screen, safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0), reduceMotion: false,
            list: PlaneGameList(stage: { nil }, threads: { 0 }))
        let renderer = ImageRenderer(
            content: ZStack {
                PlaneGameView(model: model)
                PlaneGameOverCard(
                    result: PlaneGameResult(score: 0, best: 0, isNewBest: false), playAgain: {}, exit: {})
                PlaneGamePauseCard(resume: {}, exit: {})
            }
            .frame(width: screen.width, height: screen.height))
        renderer.scale = 1
        _ = renderer.cgImage
    }
}
