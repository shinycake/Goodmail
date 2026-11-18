import PlaneGame
import SwiftUI

/// The game screen: paper over the window, the canvas, the envelopes while they fold, the scene's paper planes
/// fading with the paper, the HUD and the game over card. A drag anywhere steers and fires. It fills the window,
/// so its coordinates are the window's.
struct PlaneGameView: View {
    let model: PlaneGameModel

    var body: some View {
        let look = model.look
        ZStack {
            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemBackground).opacity(look.paper)
                PlaneGameCanvas(frame: look.canvas)
                if let pile = look.pile {
                    PlaneGamePileView(pile: pile)
                }
                if let flights = look.flights {
                    let field = model.handoff.stage.field
                    PaperPlanes(scene: flights.scene)
                        .frame(width: field.width, height: field.height)
                        .opacity(flights.opacity)
                        .position(x: field.midX, y: field.midY)
                }
                Text("Drag to fly", tableName: "PlaneGame", bundle: .module, comment: "Hint at the start of the game")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .opacity(model.hint)
                    .position(model.hintCenter)
                    .accessibilityHidden(model.hint == 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            VStack(spacing: 0) {
                PlaneGameHUD(
                    lives: model.world.lives, score: model.world.score, mailWaiting: model.mailWaiting,
                    mailArrivals: model.mailArrivals, exit: model.exit)
                if let boss = model.world.boss {
                    PlaneGameBossMeter(line: PlaneGameBossLine(boss: boss, reduceMotion: model.reduceMotion))
                }
                Spacer()
            }
            .opacity(look.hud)
            if let card = model.card {
                PlaneGameOverCard(result: card.result, playAgain: model.playAgain, exit: model.exit)
                    .opacity(card.opacity)
                    .transition(CardTransition())
            }
        }
        .animation(.smooth(duration: 0.3), value: model.phase.isOver)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { model.touch(sideways: $0.translation.width) }
                .onEnded { _ in model.release() }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: model.kills)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.catches)
        .sensoryFeedback(.warning, trigger: model.hits)
        .sensoryFeedback(.success, trigger: model.bossesDown)
    }
}

/// The Inbox's envelopes, posed by the takeoff or the landing at their place on the screen. The real pile, so the
/// first and last frames are the scene's own.
private struct PlaneGamePileView: View {
    let pile: PlaneGameLook.Pile

    var body: some View {
        EnvelopePile(width: pile.width, fan: pile.pose.fan)
            .offset(y: -pile.pose.lift)
            // Never quite zero across, which would leave nothing to scale back from.
            .scaleEffect(x: pile.pose.scale * max(pile.pose.width, 0.001), y: pile.pose.scale)
            .opacity(pile.pose.opacity)
            .position(pile.center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The card fades in, growing the last bit of the way to its size. On the way out it fades with what was in play,
/// so by the time it is taken away there is nothing left of it to see.
private struct CardTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .scaleEffect(phase.isIdentity ? 1 : 0.94)
    }
}

extension PlaneGamePhase {
    /// Whether the card shows.
    fileprivate var isOver: Bool {
        if case .over = self { true } else { false }
    }
}
