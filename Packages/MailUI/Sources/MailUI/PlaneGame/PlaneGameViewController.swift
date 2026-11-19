import PlaneGame
import SwiftUI
import UIKit

/// The paper plane game, presented over the whole window with no animation, so it covers the bars, owns every touch
/// and leaves the mailbox list untouched underneath. It owns the frame clock: a display link that steps the model once
/// a frame while the scene is active.
final class PlaneGameViewController: UIViewController {
    private let model: PlaneGameModel
    /// Takes the envelopes and doodles from the Inbox Zero scene that shows, as the game first draws them and every
    /// frame after, since the Inbox can be built anew under the game with a scene of its own.
    private let takeOver: () -> Void
    /// Gives the Inbox Zero scene its envelopes and doodles back.
    private let handBack: () -> Void
    private var clock = FrameClock.stopped
    /// What the status bar and home indicator were last told: whether the paper covers the window.
    private var coversWindow = false

    /// A game taking over from `handoff`, drawn in `window`, asking `list` how the list it came from is doing.
    init(
        handoff: InboxZeroHandoff, window: UIWindow, list: PlaneGameList, takeOver: @escaping () -> Void,
        handBack: @escaping () -> Void
    ) {
        model = PlaneGameModel(
            handoff: handoff, screen: window.bounds.size, safeArea: window.safeAreaInsets,
            reduceMotion: SystemAccessibility.reducesMotion, list: list)
        self.takeOver = takeOver
        self.handBack = handBack
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        let host = UIHostingController(rootView: PlaneGameView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        model.resize(screen: view.bounds.size, safeArea: view.safeAreaInsets)
    }

    /// In the window and laid out, with nothing on screen yet: the scene stops drawing its envelopes and doodles in
    /// the same frame the game first draws them. Any earlier leaves a gap of a few frames with neither; any later, a
    /// double image.
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        takeOver()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        clock = .running(link, lastFrame: nil)
        let scene = view.window?.windowScene
        NotificationCenter.default.addObserver(
            self, selector: #selector(sceneWillDeactivate), name: UIScene.willDeactivateNotification, object: scene)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sceneDidActivate), name: UIScene.didActivateNotification, object: scene)
        becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopClock()
    }

    // MARK: The frame clock

    @objc private func step(_ link: CADisplayLink) {
        // Handed back last frame, so the scene underneath is drawing its envelopes and doodles again.
        if model.phase == .gone {
            stopClock()
            dismiss(animated: false)
            return
        }
        // The time since the last frame stepped, so a dropped frame doesn't slow the game down; the model caps it, so
        // a hitch never teleports anything. The first frame, with nothing before it, steps by its own length.
        guard case .running(_, let lastFrame) = clock else { return }
        clock = .running(link, lastFrame: link.timestamp)
        model.tick(by: lastFrame.map { link.timestamp - $0 } ?? link.targetTimestamp - link.timestamp)
        if model.phase == .gone { handBack() } else { takeOver() }
        updateChrome()
    }

    private func stopClock() {
        if case .running(let link, _) = clock { link.invalidate() }
        clock = .stopped
        NotificationCenter.default.removeObserver(self)
    }

    /// Nothing moves while the app is in the background or a system sheet is over it, and the game waits paused for
    /// the reader to come back to it.
    @objc private func sceneWillDeactivate() {
        model.pause()
        guard case .running(let link, _) = clock else { return }
        link.isPaused = true
    }

    /// Picks up from the frame after the pause, not from before it.
    @objc private func sceneDidActivate() {
        guard case .running(let link, _) = clock else { return }
        link.isPaused = false
        clock = .running(link, lastFrame: nil)
    }

    // MARK: The system around it

    /// The status bar fades away and the home indicator dims while the paper covers the window.
    private func updateChrome() {
        guard model.coversWindow != coversWindow else { return }
        coversWindow = model.coversWindow
        UIView.animate(withDuration: 0.25) { self.setNeedsStatusBarAppearanceUpdate() }
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    override var prefersStatusBarHidden: Bool { coversWindow }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool { coversWindow }
    /// A drag that starts at an edge steers the plane before it opens Control Center or goes home.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    // MARK: The way out and the pause

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(askToLeave))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }

    @objc private func askToLeave() {
        model.exit()
    }

    override func accessibilityPerformEscape() -> Bool {
        model.exit()
        return true
    }

    /// VoiceOver's two finger double tap pauses the game, and carries it on after the countdown.
    override func accessibilityPerformMagicTap() -> Bool {
        if case .paused(_, .card) = model.phase { model.resume() } else { model.pause() }
        return true
    }
}

/// The display link that steps the game once a frame, while the screen is on display.
private enum FrameClock {
    case stopped
    /// Ticking. `lastFrame` is when the frame it last stepped was shown, or `nil` before its first frame since it
    /// started or picked up after a pause.
    case running(CADisplayLink, lastFrame: CFTimeInterval?)
}
