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
        NotificationCenter.default.addObserver(
            self, selector: #selector(sceneDidEnterBackground(_:)), name: UIScene.didEnterBackgroundNotification,
            object: nil)
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
        stage.layout()
    }

    /// A motion under way finishes at once at its end before the window changes size; the next one measures the
    /// pill afresh.
    public override func viewWillTransition(
        to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        stage.settleNow()
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

    /// A tap on the pill: one message opens out of it, several are laid out to pick from.
    private func reopen() {
        guard shelf.state == .minimized, !stage.isMoving, let front = shelf.entries.first else { return }
        guard shelf.entries.count == 1 else {
            shelf.reopen()
            shelfChanged()
            return showPicker()
        }
        // The shelf writes it once the card covers the pill, which then hides under it.
        stage.open(
            front.composer,
            from: .dock(undocked: { [weak self] in
                self?.shelf.reopen()
                self?.shelfChanged()
            }))
    }

    /// Lays the drafts out to pick one.
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
        self.picker = picker
        topPresenter.present(picker, animated: true)
    }

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
        // The pill, behind the picker, already counts one fewer.
        closePicker { [weak self] in self?.stage.open(composer, from: .dock(undocked: {})) }
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

    /// Shows how many messages wait on every pill, and hands what the shelf holds to `keep`.
    private func shelfChanged() {
        dock.show(shelf.minimizedCount)
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
        guard stage.composer === composer else {
            didMinimize(composer)
            next?()
            return
        }
        stage.leave(to: .dock(docked: { [weak self] in self?.didMinimize(composer) })) { _ in next?() }
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
        if stage.composer === composer { stage.leave(to: .away) }
        switch shelf.state {
        case .choosing: picker?.show(shelf.entries.map(\.draft))
        case .empty, .minimized, .writing: closePicker()
        }
    }
}
