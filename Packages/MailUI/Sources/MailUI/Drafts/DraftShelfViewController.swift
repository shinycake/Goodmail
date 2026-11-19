public import MailCore
public import UIKit

/// The window's root: the mail screens, and over them, once a message is minimized, a capsule in the bottom toolbar
/// between Search and Compose to swipe up or tap to open it again (above the toolbar where there's no room in it).
/// Several messages can wait there; opening several lays them out to pick one.
public final class DraftShelfViewController: UIViewController {
    /// The messages in progress. Only the methods below change it, each presenting what its new state shows.
    private var shelf = DraftShelf<ComposeViewController>()
    /// The minimized messages: every one in progress but the one on the composer's card.
    private let bar = DraftPillView(interactive: true)
    /// The message being written, on its card over the mail screens, and its moves to and from the bar.
    private lazy var stage = ComposerStage(shelf: self, dock: bar)
    /// Keeps the messages in progress, the last one written first, so they come back after the app is closed. Told
    /// after each change, and as the window leaves the screen with the one being written as it stands then.
    public var keep: (([Draft]) -> Void)?
    /// Starts a new message from the account, after the picker's New Message button. It comes back through `open`.
    public var newMessage: ((AccountID) -> Void)?

    /// The mail screens, or the welcome screen before there is an account.
    public var content: UIViewController? {
        didSet {
            guard content !== oldValue else { return }
            oldValue?.willMove(toParent: nil)
            oldValue?.view.removeFromSuperview()
            oldValue?.removeFromParent()
            (oldValue as? any DraftDockSite)?.onBottomLineChange = nil
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
        view.backgroundColor = .systemBackground
        bar.isHidden = true
        bar.onOpen = { [weak self] in self?.reopen() }
        bar.onDrag = { [weak self] in self?.reopen(following: $0) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(sceneDidEnterBackground(_:)), name: UIScene.didEnterBackgroundNotification,
            object: nil)
        view.addSubview(bar)
        stage.install()
        stage.planLeaving = { [unowned self] in planLeaving($0) }
        stage.onChange = { [unowned self] in updateBar() }
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
        // The content lays out first, telling the bar its line if that changed; without a line, it floats.
        if !(content is any DraftDockSite) { placeBar() }
        stage.layout()
    }

    public override var childForStatusBarStyle: UIViewController? { content }
    /// The mail screens decide whether their bars may run down the side, as on iPhone Duo.
    public override var childForPreferredVerticalBarBehavior: UIViewController? { content }

    private func embed(_ content: UIViewController) {
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(content.view, belowSubview: bar)
        content.didMove(toParent: self)
        if let site = content as? any DraftDockSite {
            site.onBottomLineChange = { [weak self] _ in self?.placeBar() }
        }
        placeBar()
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

    private func write(_ composer: ComposeViewController) {
        composer.host = self
        shelf.open(composer.viewModel.draft, in: composer)
        shelfChanged()
        guard let writing = shelf.writing?.composer else { return }
        stage.open(writing, from: .below)
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
        stage.open(front.composer, from: .dock(showing: waiting), following: pan) { [weak self] opened in
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
            stage.open(composer, from: .dock(showing: [composer.written]))
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
        updateBar()
        keep?(inProgress)
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

    /// The messages waiting in the bar, the last one written first: all in progress but the one on the card, being
    /// written or on its way.
    private var waiting: [Draft] {
        shelf.entries.filter { $0.composer !== stage.composer && shelf.state != .writing($0.id) }.map(\.draft)
    }

    /// Shows the waiting messages in the bar, or hides it when none are.
    private func updateBar() {
        let drafts = waiting
        bar.show(drafts)
        bar.isHidden = drafts.isEmpty
        tellContentWhatBarTakes()
    }

    /// Puts the bar on the content's bottom line: in its toolbar's middle when there's room, else above it.
    private func placeBar() {
        let placement = DraftDockPlacement.choose(line: bottomLine, height: DraftPillView.height)
        if bar.frame != placement.frame { bar.frame = placement.frame }
        self.placement = placement
        tellContentWhatBarTakes()
    }

    /// Where the bar sits now.
    private var placement: DraftDockPlacement?

    /// The content's bottom line in this view, or, for content without one, the bottom of the screen.
    private var bottomLine: BottomLine {
        guard let site = content as? any DraftDockSite else {
            return BottomLine(
                lane: view.foldLane, ends: [], bottom: view.bounds.maxY, barsInset: view.safeAreaInsets.bottom)
        }
        let line = site.bottomLine
        let shift = site.view.convert(CGPoint.zero, to: view)
        return BottomLine(
            lane: line.lane.offsetBy(dx: shift.x, dy: shift.y),
            ends: line.ends.map { $0.offsetBy(dx: shift.x, dy: shift.y) }, bottom: line.bottom + shift.y,
            barsInset: line.barsInset)
    }

    /// Tells the content what the bar takes of its bottom, for the undo toast to keep clear of it.
    private func tellContentWhatBarTakes() {
        guard let site = content as? any DraftDockSite else { return }
        let dock: DraftDock =
            switch (bar.isHidden, placement) {
            case (true, _), (false, nil): .none
            case (false, .inToolbar): .inToolbar
            case (false, .floating(let frame)): .floating(height: frame.height)
            }
        if site.draftDock != dock { site.draftDock = dock }
    }
}

extension DraftShelfViewController: ComposerHost {
    func minimize(_ composer: ComposeViewController, then next: (() -> Void)?) {
        guard stage.composer === composer else {
            didMinimize(composer)
            next?()
            return
        }
        stage.leave(to: .dock(showing: [composer.written] + waiting)) { [weak self] _ in
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
            return ComposerStage.Leaving(destination: .dock(showing: [composer.written] + waiting)) {
                [weak self] minimized in
                if minimized { self?.didMinimize(composer) } else { composer.stayed() }
            }
        case .discard:
            return ComposerStage.Leaving(destination: .away) { discarded in
                if discarded { composer.discard() } else { composer.stayed() }
            }
        }
    }

    var canMinimize: Bool { true }

    func composerDidClose(_ composer: ComposeViewController) {
        shelf.finish(composer.viewModel.draft.id)
        shelfChanged()
        if stage.composer === composer { stage.leave(to: .away) }
        switch shelf.state {
        case .choosing: picker?.show(shelf.entries.map(\.draft))
        case .empty, .minimized, .writing: closePicker()
        }
    }
}
