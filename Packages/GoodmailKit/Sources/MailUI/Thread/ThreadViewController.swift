import MailCore
import UIKit

/// A conversation read as letters: the subject, a slim timeline of earlier messages, and cards for the ones that
/// matter now. Renders `ThreadViewModel` through Observation (ADR-011).
public final class ThreadViewController: UIViewController {
    private let viewModel: ThreadViewModel
    private let openURL: (URL) -> Void
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let subject = UILabel()
    private let metadata = UILabel()
    private var cards: [Message.ID: MessageCardView] = [:]
    private var rows: [Message.ID: TimelineRowView] = [:]
    private var observation: Task<Void, Never>?
    private var hasScrolledToFocus = false

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

    public override func updateProperties() {
        super.updateProperties()
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
        cards[id] = card
        return card
    }

    private func makeRow(for id: Message.ID) -> TimelineRowView {
        let row = TimelineRowView()
        row.addAction(UIAction { [weak self] _ in self?.viewModel.toggle(id) }, for: .primaryActionTriggered)
        rows[id] = row
        return row
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
