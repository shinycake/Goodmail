import MailCore
import PlaneGame
import SwiftUI

/// The Inbox Zero scene in the space between the list's bars. It plays the way the welcome screen does: a tap sends
/// a paper plane off and the envelopes can be dragged about. It drifts for a while after it arrives or is touched,
/// then comes to rest and stops drawing. With Reduce Motion on it holds still. Ten quick taps on the envelopes start
/// the paper plane game, which draws the envelopes and doodles while it is up, so the scene leaves only its words.
///
/// The planes its touches send off fly in the window's sky (`InboxZeroSkyView`) rather than here, so they cross the
/// pane beside the list and leave by the window's edge instead of vanishing at the list's.
struct InboxZeroScene: View {
    let showing: InboxZeroShowing
    let model: InboxZeroModel
    @State private var streak = TapStreak()
    @State private var greeting = InboxZeroGreeting(at: .now)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let layout = InboxZeroLayout(size: proxy.size, accessibilityText: dynamicTypeSize.isAccessibilitySize)
            let pileWidth = layout.pileWidth(wide: horizontalSizeClass == .regular && proxy.size.width >= 600)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || model.wake == .asleep)) {
                timeline in
                frame(at: timeline.date, layout: layout, pileWidth: pileWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            greeting = InboxZeroGreeting(at: .now)
        }
        .task(id: model.wake) {
            guard let sleepsAt = model.wake.sleepsAt,
                (try? await Task.sleep(for: .seconds(max(sleepsAt.timeIntervalSinceNow, 0)))) != nil
            else { return }
            model.rest()
            // Nothing on screen moves now, so the first game's first frame can be paid for here.
            PlaneGameWarmUp.run()
        }
    }

    private func frame(at now: Date, layout: InboxZeroLayout, pileWidth: CGFloat) -> some View {
        let entrance = InboxZeroEntrance(
            arrival: showing.arrival, elapsed: reduceMotion ? nil : now.timeIntervalSince(showing.arrivedAt))
        let stage = model.stage ?? InboxZeroStage(field: .zero, layout: layout, pileWidth: pileWidth)
        let field = stage.field.size
        let focus = stage.focus
        let playing = model.isPlaying
        let wake = model.wake
        let scene = DoodleScene(
            size: field, pokes: model.pokes, clock: reduceMotion ? .stopped : .running(now),
            rightToLeft: layoutDirection == .rightToLeft, focus: focus, energy: wake.energy(at: now),
            passInterval: InboxZeroSky.passEvery, quietFrom: wake.quietFrom, passesFrom: wake.passesFrom)
        // Beside the envelopes the doodles aren't the ring the game takes over, so they stay under its paper.
        let drawsDoodles = layout.hasDoodles && (!playing || !layout.isRinged)
        return VStack(spacing: layout.gap) {
            EnvelopePile(
                width: pileWidth, fan: scene.fan - 1 + entrance.fan, rise: scene.lift - entrance.pileDrop,
                released: model.wakeUp
            )
            .scaleEffect(entrance.pileScale)
            .opacity(playing ? 0 : entrance.pileOpacity)
            .accessibilityHidden(true)
            InboxZeroCopy(
                pointing: showing.pointing, greeting: greeting,
                title: entrance.text(appearingAt: InboxZeroEntrance.titleAppears),
                line: entrance.text(appearingAt: InboxZeroEntrance.lineAppears), go: model.go)
        }
        .padding(.top, layout.haloAbove)
        .padding(.bottom, layout.haloBelow)
        .frame(maxWidth: DoodleScene.widestField)
        .onGeometryChange(for: InboxZeroStage.self) { proxy in
            InboxZeroStage(
                field: proxy.frame(in: .named(InboxZeroStage.space)), layout: layout, pileWidth: pileWidth)
        } action: { laidOut in
            model.stage = laidOut
        }
        .background {
            if drawsDoodles {
                DoodleField(
                    doodles: layout.doodles, scene: scene,
                    reveal: entrance.reveal(from: focus, reach: hypot(field.width, field.height) / 2)
                )
                .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .onTapGesture { location in
            // Counted before the Reduce Motion guard: the game is something the reader starts on purpose. The tap that
            // completes the streak plays nothing of its own.
            if stage.pile.contains(location), streak.tap(at: .now) {
                model.play(InboxZeroHandoff(scene: scene, stage: stage))
                return
            }
            guard !reduceMotion else { return }
            model.poke(at: CGSize(width: location.x - focus.x, height: location.y - focus.y))
        }
        .opacity(entrance.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
