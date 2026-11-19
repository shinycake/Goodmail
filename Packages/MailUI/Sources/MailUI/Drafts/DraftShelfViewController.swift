public import MailCore
public import UIKit

/// The window's root: the mail screens, and under them, once a message is minimized, a bar to swipe up and open it
/// again. Several messages can wait there; swiping up on several lays them out to pick one.
public final class DraftShelfViewController: UIViewController {
    /// The messages in progress. Only the methods below change it, each presenting what its new state shows.
    private var shelf = DraftShelf<ComposeViewController>()
    private let bar = MinimizedDraftsBar()
    /// The message being written, on its card over the mail screens, and its moves to and from the bar.
    private lazy var stage = ComposerStage(shelf: self, bar: bar) { [unowned self] in layOutContent(showsBar: $0) }
    /// Ends the content at the bar while messages are minimized, else at the bottom of the screen.
    private var contentBottom: NSLayoutConstraint?
    /// Keeps the messages in progress, the last one written first, so they come back after the app is closed. Told
    /// after each change, and as the window leaves the screen with the one being written as it stands then.
    public var keep: (([Draft]) -> Void)?
    /// The bar's sides, from the physical left and right: inside the safe area, and off iPhone Duo's fold (`FoldLane`).
    private var barLeft: NSLayoutConstraint!
    private var barRight: NSLayoutConstraint!
    /// Starts a new message from the account, after the picker's New Message button. It comes back through `open`.
    public var newMessage: ((AccountID) -> Void)?

    /// The mail screens, or the welcome screen before there is an account.
    public var content: UIViewController? {
        didSet {
            guard content !== oldValue else { return }
            oldValue?.willMove(toParent: nil)
            oldValue?.view.removeFromSuperview()
            oldValue?.removeFromParent()
            if let content { embed(content) }
            setNeedsUpdateOfVerticalBarConfiguration()
        }
    }

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .shelfBackground
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        bar.alpha = 0
        bar.onOpen = { [weak self] in self?.reopen() }
        bar.onDrag = { [weak self] in self?.reopen(following: $0) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(sceneDidEnterBackground(_:)), name: UIScene.didEnterBackgroundNotification,
            object: nil)
        view.addSubview(bar)
        // At least this tall; larger text grows the bar, and the mail screens above it shrink to fit.
        let fitted = bar.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -MinimizedDraftsBar.height)
        fitted.priority = .defaultHigh
        barLeft = bar.leftAnchor.constraint(equalTo: view.leftAnchor)
        barRight = bar.rightAnchor.constraint(equalTo: view.rightAnchor)
        NSLayoutConstraint.activate([
            barLeft,
            barRight,
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.topAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -MinimizedDraftsBar.height),
            fitted,
        ])
        stage.install()
        stage.planLeaving = { [unowned self] in planLeaving($0) }
    }

    /// Only this window's own scene keeps its drafts as it leaves, with what is being written as it stands.
    @objc private func sceneDidEnterBackground(_ notification: Notification) {
        guard let scene = notification.object as? UIScene, scene === view.window?.windowScene,
            !shelf.entries.isEmpty
        else { return }
        keep?(inProgress)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let lane = view.foldLane
        let left = lane.minX - view.bounds.minX + Self.barInset
        let right = lane.maxX - view.bounds.maxX - Self.barInset
        if barLeft.constant != left { barLeft.constant = left }
        if barRight.constant != right { barRight.constant = right }
        stage.layout()
    }

    /// The room between the bar and the sides of its lane.
    private static let barInset: CGFloat = 8

    public override var childForStatusBarStyle: UIViewController? { content }
    /// The mail screens decide whether their bars may run down the side, as on iPhone Duo.
    public override var childForPreferredVerticalBarBehavior: UIViewController? { content }

    private func embed(_ content: UIViewController) {
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        content.view.layer.cornerCurve = .continuous
        content.view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.insertSubview(content.view, belowSubview: bar)
        NSLayoutConstraint.activate([
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        content.didMove(toParent: self)
        layOutContent(showsBar: barShows)
    }

    /// Writes `composer`'s message, minimizing the one being written. A message already in progress opens in the
    /// composer it has rather than in a second one.
    public func open(_ composer: ComposeViewController) {
        switch shelf.state {
        case .empty, .minimized:
            write(composer)
        case .writing(let id):
            guard id != composer.viewModel.draft.id, let shown = shelf.writing?.composer else { return }
            // Minimizing tells the shelf through `composerDidMinimize`.
            shown.minimize { [weak self] in self?.write(composer) }
        case .choosing:
            shelf.dismissChoice()
            closePicker { [weak self] in self?.write(composer) }
        }
    }

    /// Minimizes the message being written, or puts the drafts laid out to pick from away, so the mail screens show,
    /// then calls `next`: for somewhere to go in them, such as search from a Home Screen quick action.
    public func uncover(then next: @escaping () -> Void) {
        switch shelf.state {
        case .empty, .minimized:
            next()
        case .writing:
            guard let shown = shelf.writing?.composer else { return next() }
            // Minimizing tells the shelf through `composerDidMinimize`.
            shown.minimize(then: next)
        case .choosing:
            shelf.dismissChoice()
            closePicker(then: next)
        }
    }

    private func write(_ composer: ComposeViewController) {
        composer.host = self
        shelf.open(composer.viewModel.draft, in: composer)
        shelfChanged()
        guard let writing = shelf.writing?.composer else { return }
        stage.open(writing, from: .below, barShowing: barBelongs)
    }

    /// Dragging up on the bar, or tapping it: one message comes up, following the finger if it drags; several are laid
    /// out to pick from.
    private func reopen(following pan: UIPanGestureRecognizer? = nil) {
        guard shelf.state == .minimized, let front = shelf.entries.first else { return }
        guard shelf.entries.count == 1 else {
            shelf.reopen()
            shelfChanged()
            return showPicker(following: pan)
        }
        // The shelf writes it once it's up; let go short, it stays minimized.
        stage.open(front.composer, from: .bar, barShowing: false, following: pan) { [weak self] opened in
            guard let self, opened else { return }
            shelf.reopen()
            shelfChanged()
        }
    }

    /// Lays the drafts out to pick one, coming up under the finger dragging `pan` if there is one.
    private func showPicker(following pan: UIPanGestureRecognizer? = nil) {
        let picker = DraftPickerViewController(entries: shelf.entries.map(\.draft))
        picker.onChoose = { [weak self] in self?.choose($0) }
        picker.onClose = { [weak self] id, source in self?.askToClose(id, from: source) }
        picker.onDismiss = { [weak self] in
            self?.shelf.dismissChoice()
            self?.closePicker()
        }
        picker.onNewMessage = { [weak self] in
            guard let self, let account = shelf.entries.first?.draft.accountID else { return }
            shelf.dismissChoice()
            closePicker { [weak self] in self?.newMessage?(account) }
        }
        self.picker = picker
        guard let pan else { return topPresenter.present(picker, animated: true) }
        picker.prepareToRise()
        topPresenter.present(picker, animated: false)
        let rising = ScrubbedAnimation(
            distance: view.bounds.height * 0.4, heading: .up, in: view, animations: { picker.rise() },
            landed: { [weak self, weak picker] up in
                guard let self else { return }
                pickerRise = nil
                // Let go short, the drafts go back to the bar.
                guard !up else { return }
                shelf.dismissChoice()
                picker?.dismiss(animated: false)
            })
        pickerRise = rising
        rising.run(following: pan)
    }

    /// The picker coming up under the finger, until it lands.
    private var pickerRise: ScrubbedAnimation?

    /// The picker while the drafts are laid out.
    private weak var picker: DraftPickerViewController?

    private func closePicker(then next: (() -> Void)? = nil) {
        guard let picker else {
            next?()
            return
        }
        picker.dismiss(animated: true, completion: next)
    }

    private func choose(_ id: Draft.ID) {
        shelf.choose(id)
        shelfChanged()
        guard let composer = shelf.writing?.composer else { return }
        closePicker { [weak self] in
            guard let self else { return }
            stage.open(composer, from: .bar, barShowing: barBelongs)
        }
    }

    /// The close button on a laid-out draft: delete it or keep it in Drafts, as the composer's own close button offers.
    private func askToClose(_ id: Draft.ID, from source: UIView) {
        guard let composer = shelf.entries.first(where: { $0.id == id })?.composer, let picker else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(
            UIAlertAction(
                title: String(
                    localized: "Delete Draft", table: "Compose", bundle: .module, comment: "Discards the message"),
                style: .destructive
            ) { _ in composer.deleteDraft() })
        if composer.viewModel.canSaveDraft {
            sheet.addAction(
                UIAlertAction(
                    title: String(
                        localized: "Save Draft", table: "Compose", bundle: .module,
                        comment: "Keeps the message in Drafts"),
                    style: .default
                ) { _ in composer.saveDraft() })
        }
        sheet.addAction(
            UIAlertAction(
                title: String(localized: "Cancel", table: "Drafts", bundle: .module, comment: "Keeps the draft"),
                style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        picker.present(sheet, animated: true)
    }

    /// The screen on top, which presents the composer.
    private var topPresenter: UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// Shows what the shelf holds now, and hands it to `keep`.
    private func shelfChanged() {
        let drafts = inProgress
        updateBar(drafts)
        keep?(drafts)
    }

    /// The messages in progress as written so far, the last one written first: the one being written as it stands
    /// now, the others as they were minimized.
    private var inProgress: [Draft] {
        shelf.entries.map { shelf.state == .writing($0.id) ? $0.composer.written : $0.draft }
    }

    /// Puts `composers` back in the bar behind any messages there, as minimized after the app last ran.
    public func restore(_ composers: [ComposeViewController]) {
        for composer in composers {
            composer.host = self
            shelf.shelve(composer.viewModel.draft, in: composer)
        }
        shelfChanged()
    }

    /// Shows the bar while messages are minimized, and fits the content above it. While the card moves, it moves the
    /// bar and the content with it.
    private func updateBar(_ drafts: [Draft]) {
        bar.show(drafts)
        let showsBar = barBelongs
        guard !stage.isMoving, showsBar != barShows else { return }
        bar.isHidden = false
        UIView.animate(springDuration: 0.4, bounce: Motion.bounce(0.15)) {
            self.bar.alpha = showsBar ? 1 : 0
            self.layOutContent(showsBar: showsBar)
            self.view.layoutIfNeeded()
        } completion: { _ in
            // A show that came while this hide ran leaves the bar showing.
            self.bar.isHidden = !self.barShows
        }
    }

    /// Whether the bar belongs on the screen: every message but the one being written waits in it.
    private var barBelongs: Bool {
        shelf.entries.contains { shelf.state != .writing($0.id) }
    }

    /// Whether the bar shows, or is on its way in. Its alpha holds where the last change sends it, even mid-animation.
    private var barShows: Bool {
        bar.alpha > 0
    }

    private func layOutContent(showsBar: Bool) {
        guard let content else { return }
        contentBottom?.isActive = false
        contentBottom =
            showsBar
            ? content.view.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -14)
            : content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        contentBottom?.isActive = true
        content.view.layer.cornerRadius = showsBar ? 36 : 0
        content.view.clipsToBounds = showsBar
        // The content no longer reaches the home indicator, so its bottom bars need their own room.
        content.additionalSafeAreaInsets.bottom = showsBar ? 10 : 0
    }
}

extension DraftShelfViewController: ComposerHost {
    func minimize(_ composer: ComposeViewController, then next: (() -> Void)?) {
        guard stage.composer === composer else {
            didMinimize(composer)
            next?()
            return
        }
        bar.show(inProgress)
        stage.leave(to: .bar, barShowing: true) { [weak self] _ in
            self?.didMinimize(composer)
            next?()
        }
    }

    /// The card of `composer` is in the bar: the shelf keeps the message as written.
    private func didMinimize(_ composer: ComposeViewController) {
        composer.didMinimize()
        shelf.minimize(composer.written)
        shelfChanged()
    }

    /// A drag down on the card: a message with something in it shrinks into the bar, one without slides away.
    private func planLeaving(_ composer: ComposeViewController) -> ComposerStage.Leaving {
        switch composer.startLeaving() {
        case .minimize:
            bar.show(inProgress)
            return ComposerStage.Leaving(destination: .bar, barShowing: true) { [weak self] minimized in
                if minimized { self?.didMinimize(composer) } else { composer.stayed() }
            }
        case .discard:
            return ComposerStage.Leaving(destination: .away, barShowing: barBelongs) { discarded in
                if discarded { composer.discard() } else { composer.stayed() }
            }
        }
    }

    var canMinimize: Bool { true }

    func composerDidClose(_ composer: ComposeViewController) {
        shelf.finish(composer.viewModel.draft.id)
        shelfChanged()
        if stage.composer === composer { stage.leave(to: .away, barShowing: barBelongs) }
        switch shelf.state {
        case .choosing: picker?.show(shelf.entries.map(\.draft))
        case .empty, .minimized, .writing: closePicker()
        }
    }
}

extension UIColor {
    /// Behind the mail screens while a message is minimized: the edge the bar slides out from.
    fileprivate static let shelfBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray6 : .systemGray5
    }
}
