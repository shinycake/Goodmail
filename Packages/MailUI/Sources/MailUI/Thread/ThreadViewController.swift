import MailCore
import QuickLook
import UIKit

/// A conversation read as letters: the subject, a slim timeline of earlier messages, and cards for the ones that
/// matter now. Renders `ThreadViewModel` through Observation (ADR-011).
public final class ThreadViewController: UIViewController {
    private let viewModel: ThreadViewModel
    private let openURL: (URL) -> Void
    private let starItem = UIBarButtonItem()
    /// Reply, or Edit Draft while the newest message is an unsent draft.
    private var replyItem = UIBarButtonItem()
    private lazy var editDraftItem = UIBarButtonItem(
        title: String(localized: "Edit Draft", bundle: .module, comment: "Opens a saved draft to finish it"),
        image: UIImage(systemName: "square.and.pencil"),
        primaryAction: UIAction { [weak self] _ in self?.viewModel.editDraft() })
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let subject = UILabel()
    private let metadata = UILabel()
    private var cards: [Message.ID: MessageCardView] = [:]
    private var rows: [Message.ID: TimelineRowView] = [:]
    private var observation: Task<Void, Never>?
    private var hasScrolledToFocus = false
    private var previewURL: URL?

    public init(viewModel: ThreadViewModel, openURL: @escaping (URL) -> Void) {
        self.viewModel = viewModel
        self.openURL = openURL
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    deinit {
        observation?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "thread"
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        subject.font = Typography.serif(.title1, weight: .bold)
        subject.adjustsFontForContentSizeCategory = true
        subject.numberOfLines = 0
        subject.accessibilityTraits = .header
        metadata.font = .preferredFont(forTextStyle: .subheadline)
        metadata.textColor = .secondaryLabel
        metadata.adjustsFontForContentSizeCategory = true
        metadata.numberOfLines = 0
        let header = UIStackView(arrangedSubviews: [subject, metadata])
        header.axis = .vertical
        header.spacing = 6
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        header.isLayoutMarginsRelativeArrangement = true

        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(header)
        configureToolbar()
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        // Letters keep a readable width and center in wide windows.
        let readable = scrollView.readableContentGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
        ])

        subject.setSubjectText(
            viewModel.thread.subject.isEmpty ? ThreadRowMetrics.noSubject : viewModel.thread.subject)
        observation = Task { [viewModel] in await viewModel.observe() }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
        wear(.account(viewModel.accountColor))
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    /// Archive, Trash, Snooze and Unread close the reader through the view model, which leaves the thread once.
    private func configureToolbar() {
        func item(_ action: ThreadAction) -> UIBarButtonItem {
            UIBarButtonItem(
                title: action.title, image: UIImage(systemName: action.symbol),
                primaryAction: UIAction { [weak self] _ in self?.viewModel.perform(action) })
        }
        starItem.primaryAction = UIAction { [weak self] _ in
            guard let self else { return }
            viewModel.perform(.star(!viewModel.isStarred))
        }
        replyItem = UIBarButtonItem(
            title: String(localized: "Reply", bundle: .module, comment: "Composer title for a reply"),
            image: UIImage(systemName: "arrowshape.turn.up.left"),
            primaryAction: UIAction { [weak self] _ in self?.viewModel.reply(all: false) },
            // The alternatives only: a tap is Reply, and a toolbar that overflows into More lists the primary action
            // beside these, so a Reply here would show twice.
            menu: UIMenu(children: [
                UIAction(
                    title: String(localized: "Reply All", bundle: .module, comment: "Replies to everyone"),
                    image: UIImage(systemName: "arrowshape.turn.up.left.2")
                ) { [weak self] _ in self?.viewModel.reply(all: true) },
                UIAction(
                    title: String(localized: "Forward", bundle: .module, comment: "Forwards the message"),
                    image: UIImage(systemName: "arrowshape.turn.up.right")
                ) { [weak self] _ in self?.viewModel.forward() },
            ]))
        toolbarItems = [
            item(.archive), item(.trash),
            .snooze(from: self) { [weak self] in self?.viewModel.snooze(until: $0) }, .flexibleSpace(),
            item(.markRead(false)), starItem,
            .organize(
                move: { [weak self] in self?.viewModel.move() },
                changeLabels: { [weak self] in self?.viewModel.changeLabels() }),
            .fixedSpace(0), replyItem,
        ]
    }

    public override func updateProperties() {
        super.updateProperties()
        let star: ThreadAction = .star(!viewModel.isStarred)
        starItem.image = UIImage(systemName: viewModel.isStarred ? "star.fill" : "star")
        // The title, not just an accessibility label: when the toolbar overflows into More, the menu shows it.
        starItem.title = star.title
        let answer = viewModel.draft == nil ? replyItem : editDraftItem
        if var items = toolbarItems, let last = items.indices.last, items[last] !== answer {
            items[last] = answer
            toolbarItems = items
        }
        let messages = viewModel.messages
        metadata.text = [viewModel.accountEmail, Self.countText(messages.count)]
            .filter { !$0.isEmpty }.joined(separator: " · ")

        var arranged: [UIView] = [stack.arrangedSubviews[0]]
        for message in messages {
            let dateText = viewModel.dateText(for: message)
            if viewModel.expanded.contains(message.id) {
                let card = cards[message.id] ?? makeCard(for: message.id)
                card.configure(
                    message, dateText: dateText, accountEmail: viewModel.accountEmail,
                    accountColor: viewModel.accountColor.uiColor,
                    allowsRemoteContent: viewModel.remoteContentAllowed.contains(message.id))
                arranged.append(card)
            } else {
                let row = rows[message.id] ?? makeRow(for: message.id)
                row.configure(message, dateText: dateText)
                arranged.append(row)
            }
        }
        if arranged != stack.arrangedSubviews {
            for view in stack.arrangedSubviews { view.removeFromSuperview() }
            arranged.forEach(stack.addArrangedSubview)
        }
        scrollToFocusOnce()
    }

    private func makeCard(for id: Message.ID) -> MessageCardView {
        let card = MessageCardView(attachmentData: viewModel.attachmentData)
        card.onToggle = { [weak self] in self?.viewModel.toggle(id) }
        card.onAllowRemoteContent = { [weak self] in self?.viewModel.allowRemoteContent(in: id) }
        card.openURL = openURL
        card.onOpenAttachment = { [weak self, weak card] attachment in
            guard let self, let card else { return }
            open(attachment, in: id, from: card)
        }
        cards[id] = card
        return card
    }

    private func makeRow(for id: Message.ID) -> TimelineRowView {
        let row = TimelineRowView()
        row.addAction(UIAction { [weak self] _ in self?.viewModel.toggle(id) }, for: .primaryActionTriggered)
        rows[id] = row
        return row
    }

    private func open(_ attachment: Attachment, in message: Message.ID, from card: MessageCardView) {
        card.setLoading(true, for: attachment)
        Task {
            defer { card.setLoading(false, for: attachment) }
            do {
                previewURL = try await viewModel.file(for: attachment, in: message)
                let preview = QLPreviewController()
                preview.dataSource = self
                present(preview, animated: true)
            } catch {
                let alert = UIAlertController(
                    title: String(
                        localized: "Couldn’t Open Attachment", bundle: .module,
                        comment: "Alert title when an attachment fails to download"),
                    message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(
                    UIAlertAction(title: String(localized: "OK", bundle: .module, comment: "Dismiss"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    /// Opens on the first unread message, or the newest, once the messages first arrive.
    private func scrollToFocusOnce() {
        guard !hasScrolledToFocus, let focus = viewModel.firstFocused, let card = cards[focus],
            viewModel.messages.count > 1
        else { return }
        hasScrolledToFocus = true
        view.layoutIfNeeded()
        let target = card.convert(card.bounds, to: scrollView).minY - scrollView.adjustedContentInset.top - 8
        scrollView.setContentOffset(
            CGPoint(x: 0, y: max(-scrollView.adjustedContentInset.top, target)), animated: false)
    }

    static func countText(_ count: Int) -> String {
        guard count > 1 else { return "" }
        return String(localized: "\(count) messages", bundle: .module, comment: "How many messages a thread holds")
    }
}

extension ThreadViewController: QLPreviewControllerDataSource {
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewURL == nil ? 0 : 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        (previewURL ?? URL(filePath: "/")) as NSURL
    }
}
