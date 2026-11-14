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
        title: String(
            localized: "Edit Draft", table: "Thread", bundle: .module, comment: "Opens a saved draft to finish it"),
        image: UIImage(systemName: "square.and.pencil"),
        primaryAction: UIAction { [weak self] _ in self?.viewModel.editDraft() })
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let subject = UILabel()
    private let metadata = UILabel()
    private var cards: [Message.ID: MessageCardView] = [:]
    private var rows: [Message.ID: TimelineRowView] = [:]
    /// Chat runs by their first bubble, which stays first as later messages join the run.
    private var runs: [ChatTranscript.Bubble.ID: ChatRunView] = [:]
    private var timestamps: [Date: ChatTimestampView] = [:]
    private let layoutItem = UIBarButtonItem()
    private var observation: Task<Void, Never>?
    /// The layout the reader last scrolled to the focused message in; switching layouts scrolls there again.
    private var focusedLayout: ConversationLayout?
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
        layoutItem.primaryAction = UIAction { [weak self] _ in self?.viewModel.switchLayout() }
        navigationItem.rightBarButtonItem = layoutItem
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

    /// Archive, Trash, Snooze, Mute and Unread close the reader through the view model, which leaves the thread once.
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
            title: String(localized: "Reply", table: "Thread", bundle: .module, comment: "Composer title for a reply"),
            image: UIImage(systemName: "arrowshape.turn.up.left"),
            primaryAction: UIAction { [weak self] _ in self?.viewModel.reply(all: false) },
            // The alternatives only: a tap is Reply, and a toolbar that overflows into More lists the primary action
            // beside these, so a Reply here would show twice.
            menu: UIMenu(children: [
                UIAction(
                    title: String(
                        localized: "Reply All", table: "Thread", bundle: .module, comment: "Replies to everyone"),
                    image: UIImage(systemName: "arrowshape.turn.up.left.2")
                ) { [weak self] _ in self?.viewModel.reply(all: true) },
                UIAction(
                    title: String(
                        localized: "Forward", table: "Thread", bundle: .module, comment: "Forwards the message"),
                    image: UIImage(systemName: "arrowshape.turn.up.right")
                ) { [weak self] _ in self?.viewModel.forward() },
            ]))
        toolbarItems = [
            item(.archive), item(.trash),
            .snooze(from: self) { [weak self] in self?.viewModel.snooze(until: $0) }, .flexibleSpace(),
            item(.markRead(false)), starItem,
            .organize(
                move: { [weak self] in self?.viewModel.move() },
                changeLabels: { [weak self] in self?.viewModel.changeLabels() },
                mute: { [weak self] in self?.viewModel.muteAction },
                perform: { [weak self] in self?.viewModel.perform($0) }),
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

        let other = viewModel.layout.other
        layoutItem.image = UIImage(systemName: other == .chat ? "bubble.left.and.bubble.right" : "doc.plaintext")
        layoutItem.title = String(
            localized: "Show as \(other.title)", table: "Thread", bundle: .module,
            comment: "Switches one conversation's layout; the argument is Classic or Chat")
        stack.spacing = viewModel.layout == .chat ? 10 : 12

        let header = stack.arrangedSubviews[0]
        let arranged =
            [header] + (viewModel.layout == .chat ? chatViews(viewModel.transcript) : letterViews(messages))
        if arranged != stack.arrangedSubviews {
            for view in stack.arrangedSubviews { view.removeFromSuperview() }
            arranged.forEach(stack.addArrangedSubview)
        }
        scrollToFocusOnce()
    }

    /// Cards for the open messages and one-line rows for the rest.
    private func letterViews(_ messages: [Message]) -> [UIView] {
        var arranged: [UIView] = []
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
        return arranged
    }

    /// Timestamps and runs of bubbles, reusing the views already made for them.
    private func chatViews(_ transcript: ChatTranscript) -> [UIView] {
        let actions = ChatBubbleActions(
            openLetter: { [weak self] in self?.openLetter($0) },
            openAttachment: { [weak self] attachment, message, loading in
                self?.open(attachment, in: message, loading: loading)
            },
            showQuoted: { [weak self] in self?.scroll(to: $0, animated: true) },
            openURL: openURL)
        let times = Dictionary(
            viewModel.messages.map { ($0.id, viewModel.timestampText(for: $0.date)) },
            uniquingKeysWith: { first, _ in first })
        // Only the entries shown now keep their views, so a message that left the thread lets its views go.
        var shownRuns: [ChatTranscript.Bubble.ID: ChatRunView] = [:]
        var shownTimestamps: [Date: ChatTimestampView] = [:]
        defer { (runs, timestamps) = (shownRuns, shownTimestamps) }
        return transcript.entries.compactMap { entry -> UIView? in
            switch entry {
            case .timestamp(let date):
                let label = timestamps[date] ?? ChatTimestampView()
                shownTimestamps[date] = label
                label.text = viewModel.timestampText(for: date)
                return label
            case .run(let run):
                guard let first = run.bubbles.first else { return nil }
                let view = runs[first.id] ?? ChatRunView()
                shownRuns[first.id] = view
                view.configure(
                    run, isGroup: transcript.isGroup, accountColor: viewModel.accountColor.uiColor,
                    actions: actions, timeText: { times[$0] ?? "" })
                return view
            }
        }
    }

    /// A long or laid-out message, in full over the chat.
    private func openLetter(_ message: Message.ID) {
        let sheet = LetterSheetController(
            viewModel: viewModel, message: message, openURL: openURL,
            openAttachment: { [weak self] attachment, loading in self?.open(attachment, in: message, loading: loading) }
        )
        let navigation = UINavigationController(rootViewController: sheet)
        navigation.sheetPresentationController?.detents = [.large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    private func makeCard(for id: Message.ID) -> MessageCardView {
        let card = MessageCardView(attachmentData: viewModel.attachmentData)
        card.onToggle = { [weak self] in self?.viewModel.toggle(id) }
        card.onAllowRemoteContent = { [weak self] in self?.viewModel.allowRemoteContent(in: id) }
        card.openURL = openURL
        card.onOpenAttachment = { [weak self, weak card] attachment in
            self?.open(attachment, in: id) { card?.setLoading($0, for: attachment) }
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

    /// Downloads the file, with `loading` showing it on whatever the reader tapped, then previews it from the
    /// controller in front, which may be a letter's sheet.
    private func open(_ attachment: Attachment, in message: Message.ID, loading: @escaping (Bool) -> Void) {
        loading(true)
        Task {
            defer { loading(false) }
            do {
                previewURL = try await viewModel.file(for: attachment, in: message)
                let preview = QLPreviewController()
                preview.dataSource = self
                (presentedViewController ?? self).present(preview, animated: true)
            } catch {
                let alert = UIAlertController(
                    title: String(
                        localized: "Couldn’t Open Attachment", table: "Thread", bundle: .module,
                        comment: "Alert title when an attachment fails to download"),
                    message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(
                    UIAlertAction(
                        title: String(localized: "OK", table: "Thread", bundle: .module, comment: "Dismiss"),
                        style: .default))
                (presentedViewController ?? self).present(alert, animated: true)
            }
        }
    }

    /// Opens on the first unread message, or the newest, once the messages first arrive in each layout.
    private func scrollToFocusOnce() {
        guard focusedLayout != viewModel.layout, let focus = viewModel.firstFocused, viewModel.messages.count > 1,
            scroll(to: focus, animated: false)
        else { return }
        focusedLayout = viewModel.layout
    }

    /// Scrolls the message's card or bubble to the top, or as far as the content goes. False when it isn't shown.
    @discardableResult
    private func scroll(to message: Message.ID, animated: Bool) -> Bool {
        let shown: UIView? =
            switch viewModel.layout {
            case .classic: cards[message] ?? rows[message]
            case .chat: runs.values.lazy.compactMap { $0.view(for: message) }.first
            }
        guard let shown, shown.isDescendant(of: scrollView) else { return false }
        view.layoutIfNeeded()
        let inset = scrollView.adjustedContentInset
        let target = shown.convert(shown.bounds, to: scrollView).minY - inset.top - 8
        let bottom = max(-inset.top, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(bottom, max(-inset.top, target))), animated: animated)
        return true
    }

    static func countText(_ count: Int) -> String {
        guard count > 1 else { return "" }
        return String(
            localized: "\(count) messages", table: "Thread", bundle: .module,
            comment: "How many messages a thread holds")
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
