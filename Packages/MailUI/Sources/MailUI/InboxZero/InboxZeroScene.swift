import MailCore
import PlaneGame
import SwiftUI

/// The Inbox Zero scene in the space between the list's bars. It plays the way the welcome screen does: a tap sends
/// a paper plane off and the envelopes can be dragged about. It drifts for a while after it arrives or is touched,
/// then comes to rest and stops drawing. With Reduce Motion on it holds still. Ten quick taps on the envelopes start
/// the paper plane game, which draws the envelopes and doodles while it is up, so the scene leaves only its words.
struct InboxZeroScene: View {
    let showing: InboxZeroShowing
    let model: InboxZeroModel
    @State private var pokes = DoodlePokes()
    @State private var wake: InboxZeroWake
    @State private var streak = TapStreak()
    /// Where the envelopes and doodles are, once the scene has laid out.
    @State private var stage: InboxZeroStage?
    @State private var greeting = InboxZeroGreeting(at: .now)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// A plane passes by itself a little less often than on the welcome screen, which is seen once.
    private static let passEvery: TimeInterval = 16

    init(showing: InboxZeroShowing, model: InboxZeroModel) {
        self.showing = showing
        self.model = model
        // Seeded once: the scene that arrives is awake, and its own touches keep it so. One that arrives while the game
        // is up, as when mail came and went during it, waits asleep for the game to hand back.
        let driftStarts: Date? =
            switch showing.arrival {
            case .earned: showing.arrivedAt + InboxZeroEntrance.driftStarts
            case .found: showing.arrivedAt
            case .settled: nil
            }
        _wake = State(
            initialValue: model.isPlaying ? .asleep : .awake(since: showing.arrivedAt, rampFrom: driftStarts))
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = InboxZeroLayout(
                height: proxy.size.height, accessibilityText: dynamicTypeSize.isAccessibilitySize)
            let pileWidth = layout.pileWidth(wide: horizontalSizeClass == .regular && proxy.size.width >= 600)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || wake == .asleep)) { timeline in
                frame(at: timeline.date, layout: layout, pileWidth: pileWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            // An empty Inbox the reader just cleared sees a plane off, unless there's still unread mail to point to.
            if showing.arrival == .earned, showing.pointing == nil, !reduceMotion, !model.isPlaying {
                pokes.land(offset: .zero, time: showing.arrivedAt + InboxZeroEntrance.planeLeaves)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            greeting = InboxZeroGreeting(at: .now)
        }
        .task(id: wake) {
            guard let sleepsAt = wake.sleepsAt,
                (try? await Task.sleep(for: .seconds(max(sleepsAt.timeIntervalSinceNow, 0)))) != nil
            else { return }
            wake = .asleep
        }
        .onChange(of: model.isPlaying) { _, playing in
            // The game handed back with everything at rest, so the drift eases in from there.
            pokes = DoodlePokes()
            wake = playing ? .asleep : InboxZeroWake.asleep.woken(at: .now)
        }
    }

    private func frame(at now: Date, layout: InboxZeroLayout, pileWidth: CGFloat) -> some View {
        let entrance = InboxZeroEntrance(
            arrival: showing.arrival, elapsed: reduceMotion ? nil : now.timeIntervalSince(showing.arrivedAt))
        let stage = stage ?? InboxZeroStage(field: .zero, layout: layout, pileWidth: pileWidth)
        let field = stage.field.size
        let focus = stage.focus
        let playing = model.isPlaying
        let scene = DoodleScene(
            size: field, pokes: pokes.live, clock: reduceMotion ? .stopped : .running(now),
            rightToLeft: layoutDirection == .rightToLeft, focus: focus, energy: wake.energy(at: now),
            passInterval: Self.passEvery, quietFrom: wake.quietFrom, passesFrom: wake.passesFrom)
        return VStack(spacing: layout.gap) {
            EnvelopePile(width: pileWidth, fan: scene.fan - 1 + entrance.fan, released: wakeUp)
                .offset(y: entrance.pileDrop - scene.lift)
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
            self.stage = laidOut
            model.stage = laidOut
        }
        .background {
            if layout.isDecorated, !playing {
                DoodleField(
                    doodles: Doodle.inboxZero, scene: scene,
                    reveal: entrance.reveal(from: focus, reach: hypot(field.width, field.height) / 2)
                )
                .accessibilityHidden(true)
            }
        }
        .overlay {
            if layout.isDecorated, !playing {
                PaperPlanes(scene: scene).accessibilityHidden(true)
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
            pokes.land(offset: CGSize(width: location.x - focus.x, height: location.y - focus.y), time: .now)
            wakeUp()
        }
        .opacity(entrance.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func wakeUp() {
        wake = wake.woken(at: .now)
    }
}
