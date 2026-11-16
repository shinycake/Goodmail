public import MailCore
public import UIKit

/// The window's root: the mail screens, and under them, once a message is minimized, a bar to swipe up and open it
/// again. Several messages can wait there; swiping up on several lays them out to pick one.
public final class DraftShelfViewController: UIViewController {
    /// The messages in progress. Only the methods below change it, each presenting what its new state shows.
    private var shelf = DraftShelf<ComposeViewController>()
    private let bar = MinimizedDraftsBar()
    /// Ends the content at the bar while messages are minimized, else at the bottom of the screen.
    private var contentBottom: NSLayoutConstraint?
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
        bar.onOpen = { [weak self] in self?.reopen() }
        view.addSubview(bar)
        // At least this tall; larger text grows the bar, and the mail screens above it shrink to fit.
        let fitted = bar.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -MinimizedDraftsBar.height)
        fitted.priority = .defaultHigh
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.topAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -MinimizedDraftsBar.height),
            fitted,
        ])
    }

    public override var childForStatusBarStyle: UIViewController? { content }

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
        layOutContent(showsBar: !bar.isHidden)
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
        updateBar()
        if let writing = shelf.writing?.composer { present(writing) }
    }

    /// Swiping up on the bar: one message opens, several are laid out to pick from.
    private func reopen() {
        shelf.reopen()
        updateBar()
        switch shelf.state {
        case .writing:
            if let composer = shelf.writing?.composer { present(composer) }
        case .choosing:
            showPicker()
        case .empty, .minimized:
            break
        }
    }

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
        updateBar()
        guard let composer = shelf.writing?.composer else { return }
        closePicker { [weak self] in self?.present(composer) }
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

    private func present(_ composer: ComposeViewController) {
        let navigation = composer.navigationController ?? UINavigationController(rootViewController: composer)
        navigation.modalPresentationStyle = .pageSheet
        topPresenter.present(navigation, animated: true)
    }

    /// The screen on top, which presents the composer.
    private var topPresenter: UIViewController {
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// Shows the bar while messages are minimized, and fits the content above it.
    private func updateBar() {
        bar.show(shelf.entries.map(\.draft))
        // Every message but the one being written waits in the bar.
        let showsBar = shelf.entries.contains { shelf.state != .writing($0.id) }
        guard showsBar == bar.isHidden else { return }
        if showsBar { bar.isHidden = false }
        UIView.animate(springDuration: 0.4, bounce: 0.15) {
            self.bar.alpha = showsBar ? 1 : 0
            self.layOutContent(showsBar: showsBar)
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.bar.isHidden = !showsBar
        }
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
    func composerDidMinimize(_ composer: ComposeViewController) {
        shelf.minimize(composer.written)
        updateBar()
    }

    func composerDidClose(_ composer: ComposeViewController) {
        shelf.finish(composer.viewModel.draft.id)
        updateBar()
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
