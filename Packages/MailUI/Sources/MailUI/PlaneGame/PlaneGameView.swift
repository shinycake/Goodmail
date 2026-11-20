import PlaneGame
import SwiftUI

/// The game screen: paper over the window, the canvas, the envelopes while they fold, the scene's paper planes
/// fading with the paper, the HUD, and the card over a paused game or a game over, the countdown before a paused game
/// carries on and the question before leaving it. A drag anywhere steers and fires. It fills the window,
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
                    PaperPlanes(scene: flights.scene)
                        .frame(width: flights.frame.width, height: flights.frame.height)
                        .opacity(flights.opacity)
                        .position(x: flights.frame.midX, y: flights.frame.midY)
                }
                VStack(spacing: 4) {
                    Text(
                        "Drag to fly", tableName: "PlaneGame", bundle: .module, comment: "Hint at the start of the game"
                    )
                    if model.hasKeyboard {
                        Text(
                            "Arrow keys to fly, Space to fire", tableName: "PlaneGame", bundle: .module,
                            comment: "Hint at the start of the game, shown when a keyboard is connected")
                    }
                }
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(model.hint)
                .position(model.hintCenter)
                .accessibilityHidden(model.hint == 0)
                if let boss = model.world.boss,
                    case let beat = PlaneGameBossTitleBeat(age: boss.age, reduceMotion: model.reduceMotion),
                    beat.opacity > 0
                {
                    let field = model.world.field
                    PlaneGameBossTitle(
                        kind: boss.kind, round: model.world.round,
                        center: PlaneGameBossTitle.center(for: boss, on: field),
                        width: field.lanes.upperBound - field.lanes.lowerBound, beat: beat)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            VStack(spacing: 0) {
                PlaneGameHUD(
                    lives: model.world.lives, score: model.world.score, mailWaiting: model.mailWaiting,
                    mailArrivals: model.mailArrivals, canPause: model.canPause, pause: model.pause,
                    leave: model.askToLeave)
                if let boss = model.world.boss {
                    PlaneGameBossMeter(line: PlaneGameBossLine(boss: boss, reduceMotion: model.reduceMotion))
                } else {
                    PlaneGameRoundLabel(round: model.world.round)
                        .padding(.top, 2)
                }
                Spacer()
            }
            .opacity(look.hud)
            if let card = model.card {
                PlaneGameOverCard(result: card.result, playAgain: model.playAgain, exit: model.exit)
                    .opacity(card.opacity)
                    .transition(CardTransition())
            }
            if model.phase.showsPauseCard {
                PlaneGamePauseCard(resume: model.resume, exit: model.exit)
                    .transition(CardTransition())
            }
            if case .paused(_, .countingDown(let left)) = model.phase {
                PlaneGameCountdown(left: left, reduceMotion: model.reduceMotion)
            }
        }
        .animation(.smooth(duration: 0.3), value: model.phase.isOver)
        .animation(.smooth(duration: 0.3), value: model.phase.showsPauseCard)
        .alert(
            Text(
                "Leave the Game?", tableName: "PlaneGame", bundle: .module,
                comment: "Asked before leaving a paper plane game in play"),
            isPresented: Binding(
                get: { model.phase.isAskingToLeave },
                // Dismissed without an answer, as it is when the window closes, counts as staying.
                set: { if !$0 { model.stay() } })
        ) {
            Button(role: .destructive, action: model.exit) {
                Text(
                    "Leave", tableName: "PlaneGame", bundle: .module,
                    comment: "Leaves a paper plane game in play")
            }
            Button(role: .cancel, action: model.stay) {
                Text(
                    "Keep Playing", tableName: "PlaneGame", bundle: .module,
                    comment: "Stays in the paper plane game instead of leaving it")
            }
        } message: {
            Text(
                "You'll lose your progress in this game.", tableName: "PlaneGame", bundle: .module,
                comment: "Why the paper plane game asks before leaving it")
        }
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
        // A tick as each number of the countdown shows.
        .sensoryFeedback(.impact(weight: .light), trigger: model.phase.countdown) { _, count in count != nil }
        // A boss's title is drawn over the field, so VoiceOver hears it.
        .onChange(of: model.world.boss?.number) { before, number in
            guard before == nil, let number, let boss = model.world.boss else { return }
            SystemAccessibility.announce(
                String(
                    localized: "Round \(number), \(PlaneGameBossName.of(boss.kind))", table: "PlaneGame",
                    bundle: .module,
                    comment:
                        "Read by VoiceOver as a boss arrives in the paper plane game: the round and the boss's name"))
        }
        // VoiceOver's focus stays where the pause card was, so the countdown is said as it starts.
        .onChange(of: model.phase.countdown) { before, count in
            guard before == nil, let count else { return }
            SystemAccessibility.announce(
                String(
                    localized: "Resuming in \(count)", table: "PlaneGame", bundle: .module,
                    comment: "The countdown before a paused paper plane game carries on, read by VoiceOver"))
        }
    }
}

/// The Inbox's envelopes, posed by the takeoff or the landing at their place on the screen. The real pile, so the
/// first and last frames are the scene's own.
private struct PlaneGamePileView: View {
    let pile: PlaneGameLook.Pile

    var body: some View {
        EnvelopePile(width: pile.width, fan: pile.pose.fan, rise: pile.pose.lift)
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

    /// Whether the pause card shows: while it waits, and under the question asked from it.
    fileprivate var showsPauseCard: Bool {
        switch self {
        case .paused(_, .card), .paused(_, .askingToLeave(staying: .card)): true
        case .flying, .paused, .over, .leaving, .gone: false
        }
    }

    /// Whether the game asks before it leaves.
    fileprivate var isAskingToLeave: Bool {
        if case .paused(_, .askingToLeave) = self { true } else { false }
    }

    /// The number the countdown shows, or `nil` when it isn't counting down.
    fileprivate var countdown: Int? {
        if case .paused(_, let hold) = self { hold.count } else { nil }
    }
}
