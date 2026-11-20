public import MailCore
public import UIKit

/// The window's root: the mail screens, and over them the message being written. A minimized message waits in the
/// drafts pill at the leading end of the mail list's toolbar; tapping it opens the message again, or, with several
/// waiting, lays them out to pick one.
public final class DraftShelfViewController: UIViewController {
    /// The messages in progress. Only the methods below change it, each presenting what its new state shows.
    private var shelf = DraftShelf<ComposeViewController>()
    /// Tells the mail lists' drafts pills how many messages are minimized, and hears one tapped.
    public let dock = DraftsDock()
    /// The message being written, on its card over the mail screens, and its moves to and from the pill.
    private lazy var stage = ComposerStage(shelf: self, dock: dock)
    /// Keeps the messages in progress, the last one written first, so they come back after the app is closed. Told
    /// after each change, and as the window leaves the screen with the one being written as it stands then.
    public var keep: (([Draft]) -> Void)?
    /// Starts a new message from the account, after the picker's New Message button. It comes back through `open`.
    public var newMessage: ((AccountID) -> Void)?
    /// Starts a new message holding what was dropped on the mail screens while none is being written. It comes back
    /// through `open`.
    public var newMessageHolding: ((SharedItems.Loaded) -> Void)?
    /// Takes what other apps drop on the window that nothing on it took.
    private lazy var intake = ContentIntake(
        room: { [unowned self] in dropRoom }, receive: { [unowned self] in dropped($0) })

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
        view.backgroundColor = .systemBackground
        dock.onOpen = { [weak self] in self?.reopen() }
        dock.onDismissAll = { [weak self] source in self?.askToDismissAll(from: source) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(sceneDidEnterBackground(_:)), name: UIScene.didEnterBackgroundNotification,
            object: nil)
        stage.install()
        view.addInteraction(intake.interaction)
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
        stage.layout()
    }

    /// A motion under way finishes at once at its end before the window changes size; the next one measures the
    /// pill afresh.
    public override func viewWillTransition(
        to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        // The picker first: a fold landing can open a message, which then settles with the rest.
        settlePicker()
        stage.settleEverything()
    }

    public override var childForStatusBarStyle: UIViewController? { content }
    /// The mail screens decide whether their bars may run down the side, as on iPhone Duo.
    public override var childForPreferredVerticalBarBehavior: UIViewController? { content }

    private func embed(_ content: UIViewController) {
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(content.view, at: 0)
        NSLayoutConstraint.activate([
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        content.didMove(toParent: self)
    }

    /// The message being written, which takes what is dropped beside its card.
    var writing: ComposeViewController? { shelf.writing?.composer }

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
        stage.open(writing, from: .below)
    }

    /// A tap on the pill: one message opens out of it, several are laid out to pick from. A motion under way ends
    /// first, so the tap counts from where it lands.
    private func reopen() {
        // A fold going on lets taps through to the pill; landing it first runs what it was to lead to, such as a new
        // message, before the shelf is read.
        settlePicker()
        stage.settleNow()
        guard shelf.state == .minimized else { return }
        shelf.reopen()
        guard let writing = shelf.writing?.composer else {
            shelfChanged()
            return showPicker()
        }
        // The shelf writes it now, so a message opened while it grows minimizes it first. The pill lets it go once
        // the card lands open over it.
        stage.open(writing, from: .dock(undocked: { [weak self] in self?.shelfChanged() }))
    }

    /// The picker on screen, over the mail screens and under the composer's card. It is `.out` exactly while the
    /// shelf is `.choosing`; once the shelf leaves that state, the picker plays out its fold as `.returning`. Only
    /// `showPicker`, `closePicker` and `remove` change it; how the cards move is the picker's own business.
    private var laid = Laid.away

    private enum Laid {
        case away
        /// Laid out, or coming out of the pill.
        case out(DraftPickerViewController)
        /// Going back into the pill, picked from or not.
        case returning(DraftPickerViewController)
    }

    /// Ends any fan or fold at once. A fold landing removes its picker and runs what it was to lead to.
    private func settlePicker() {
        switch laid {
        case .away: break
        case .out(let picker), .returning(let picker): picker.settleNow()
        }
    }

    /// Lays the drafts out to pick one, coming out of the pill.
    private func showPicker() {
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
        addChild(picker)
        picker.view.frame = view.bounds
        picker.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stage.place(picker.view)
        picker.didMove(toParent: self)
        picker.view.layoutIfNeeded()
        laid = .out(picker)
        picker.fanOut(from: pillFrame)
    }

    /// Folds the laid-out drafts back into the pill, all but `chosen`, then calls `next`.
    private func closePicker(leaving chosen: Draft.ID? = nil, then next: (() -> Void)? = nil) {
        guard case .out(let picker) = laid else {
            next?()
            return
        }
        laid = .returning(picker)
        picker.fold(into: pillFrame, leaving: chosen) { [weak self] in
            self?.remove(picker)
            next?()
        }
    }

    private func remove(_ picker: DraftPickerViewController) {
        picker.willMove(toParent: nil)
        picker.view.removeFromSuperview()
        picker.removeFromParent()
        if case .returning(let returning) = laid, returning === picker { laid = .away }
    }

    /// The pill on show, or its corner of the screen when none is.
    private var pillFrame: CGRect { dock.spot(in: view)?.frame ?? stage.corner }

    /// A laid-out draft was picked: its card grows into the composer as the others fold back into the pill, which
    /// counts one fewer once the composer covers it.
    private func choose(_ id: Draft.ID) {
        guard case .out(let picker) = laid else { return }
        picker.settleNow()
        let from = picker.frame(of: id, in: view)
        shelf.choose(id)
        guard let composer = shelf.writing?.composer else { return }
        closePicker(leaving: id)
        let undocked: () -> Void = { [weak self] in self?.shelfChanged() }
        stage.open(
            composer,
            from: from.map { .card($0, cornerRadius: DraftCard.cornerRadius, undocked: undocked) }
                ?? .dock(undocked: undocked))
    }

    /// The close button on a laid-out draft: delete it or keep it in Drafts, as the composer's own close button offers.
    private func askToClose(_ id: Draft.ID, from source: UIView) {
        guard case .out(let picker) = laid, let entry = shelf.entries.first(where: { $0.id == id }) else { return }
        askToDismiss([entry.composer], from: source, in: picker)
    }

    /// Dismiss All in the pill's menu: the same choice once, for every minimized message.
    private func askToDismissAll(from source: UIView) {
        let minimized = shelf.entries.filter { shelf.state != .writing($0.id) }.map(\.composer)
        guard !minimized.isEmpty else { return }
        askToDismiss(minimized, from: source, in: self)
    }

    /// Asks whether to delete `composers`' messages or keep them in Drafts, and does it to each of them.
    private func askToDismiss(_ composers: [ComposeViewController], from source: UIView, in presenter: UIViewController)
    {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let canSave = composers.allSatisfy(\.viewModel.canSaveDraft)
        for dismissal in DraftDismissal.allCases where dismissal != .save || canSave {
            sheet.addAction(
                UIAlertAction(title: dismissal.title(count: composers.count), style: dismissal.style) { _ in
                    for composer in composers { dismissal.apply(to: composer) }
                })
        }
        sheet.addAction(
            UIAlertAction(
                title: String(localized: "Cancel", table: "Drafts", bundle: .module, comment: "Keeps the draft"),
                style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        presenter.present(sheet, animated: true)
    }

    /// Shows the messages that wait on every pill, and hands what the shelf holds to `keep`.
    private func shelfChanged() {
        dock.show(shelf.minimized)
        keep?(inProgress)
    }

    /// The messages in progress as written so far, the last one written first: the one being written as it stands
    /// now, the others as they were minimized.
    private var inProgress: [Draft] {
        shelf.entries.map { shelf.state == .writing($0.id) ? $0.composer.written : $0.draft }
    }

    /// Puts `composers` back in the pill behind any messages there, as minimized after the app last ran.
    public func restore(_ composers: [ComposeViewController]) {
        for composer in composers {
            composer.host = self
            shelf.shelve(composer.viewModel.draft, in: composer)
        }
        shelfChanged()
    }

}

extension DraftShelfViewController: ComposerHost {
    func minimize(_ composer: ComposeViewController, then next: (() -> Void)?) {
        // A minimize under way finishes first: a message that has already drained into the pill ends minimized
        // below rather than waiting to leave forever.
        stage.settleNow()
        guard stage.composer === composer else {
            didMinimize(composer)
            next?()
            return
        }
        stage.leave(composer, to: .dock(docked: { [weak self] in self?.didMinimize(composer) })) { _ in next?() }
    }

    /// The card of `composer` reached the pill, or left by its corner: the shelf keeps the message as written, and
    /// the pill shows it.
    private func didMinimize(_ composer: ComposeViewController) {
        composer.didMinimize()
        shelf.minimize(composer.written)
        shelfChanged()
        SystemAccessibility.announce(
            String(
                localized: "Message minimized", table: "Drafts", bundle: .module,
                comment: "VoiceOver announcement after the composer shrinks into the drafts pill"))
    }

    /// A drag down on the card: a message with something in it shrinks into the pill, one without slides away.
    private func planLeaving(_ composer: ComposeViewController) -> ComposerStage.Leaving {
        switch composer.startLeaving() {
        case .minimize:
            return ComposerStage.Leaving(destination: .dock(docked: { [weak self] in self?.didMinimize(composer) })) {
                minimized in if !minimized { composer.stayed() }
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
        if stage.composer === composer { stage.leave(composer, to: .away) }
        // Laid out means choosing, which a finished draft ends only when it was the last one.
        guard case .out(let picker) = laid else { return }
        if shelf.state == .choosing { picker.show(shelf.entries.map(\.draft)) } else { closePicker() }
    }
}
